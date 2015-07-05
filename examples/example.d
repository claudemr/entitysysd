import entitysysd;
/+
float r(int a, float b = 0) {
  return static_cast<float>(std::rand() % (a * 1000) + b * 1000) / 1000.0;
}


struct Body {
  Body(const sf::Vector2f &position, const sf::Vector2f &direction, float rotationd = 0.0)
    : position(position), direction(direction), rotationd(rotationd) {}

  sf::Vector2f position;
  sf::Vector2f direction;
  float rotation = 0.0, rotationd;
};


struct Renderable {
  explicit Renderable(std::unique_ptr<sf::Shape> shape) : shape(std::move(shape)) {}

  std::unique_ptr<sf::Shape> shape;
};


struct Particle {
  explicit Particle(sf::Color colour, float radius, float duration)
      : colour(colour), radius(radius), alpha(colour.a), d(colour.a / duration) {}

  sf::Color colour;
  float radius, alpha, d;
};


struct Collideable {
  explicit Collideable(float radius) : radius(radius) {}

  float radius;
};


// Emitted when two entities collide.
struct CollisionEvent {
  CollisionEvent(ex::Entity left, ex::Entity right) : left(left), right(right) {}

  ex::Entity left, right;
};


class SpawnSystem : public ex::System<SpawnSystem> {
public:
  explicit SpawnSystem(sf::RenderTarget &target, int count) : size(target.getSize()), count(count) {}

  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    int c = 0;
    ex::ComponentHandle<Collideable> collideable;
    for (ex::Entity entity : es.entities_with_components<Collideable>()) c++;

    for (int i = 0; i < count - c; i++) {
      ex::Entity entity = es.create();

      // Mark as collideable (explosion particles will not be collideable).
      collideable = entity.assign<Collideable>(r(10, 5));

      // "Physical" attributes.
      entity.assign<Body>(
        sf::Vector2f(r(size.x), r(size.y)),
        sf::Vector2f(r(100, -50), r(100, -50)));

      // Shape to apply to entity.
      std::unique_ptr<sf::Shape> shape(new sf::CircleShape(collideable->radius));
      shape->setFillColor(sf::Color(r(128, 127), r(128, 127), r(128, 127)));
      shape->setOrigin(collideable->radius, collideable->radius);
      entity.assign<Renderable>(std::move(shape));
    }
  }

private:
  sf::Vector2u size;
  int count;
};


// Updates a body's position and rotation.
struct BodySystem : public ex::System<BodySystem> {
  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    ex::ComponentHandle<Body> body;
    for (ex::Entity entity : es.entities_with_components(body)) {
      body->position += body->direction * static_cast<float>(dt);
      body->rotation += body->rotationd * dt;
    }
  };
};


// Bounce bodies off the edge of the screen.
class BounceSystem : public ex::System<BounceSystem> {
public:
  explicit BounceSystem(sf::RenderTarget &target) : size(target.getSize()) {}

  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    ex::ComponentHandle<Body> body;
    for (ex::Entity entity : es.entities_with_components(body)) {
      if (body->position.x + body->direction.x < 0 ||
          body->position.x + body->direction.x >= size.x)
        body->direction.x = -body->direction.x;
      if (body->position.y + body->direction.y < 0 ||
          body->position.y + body->direction.y >= size.y)
        body->direction.y = -body->direction.y;
    }
  }

private:
  sf::Vector2u size;
};


// Determines if two Collideable bodies have collided. If they have it emits a
// CollisionEvent. This is used by ExplosionSystem to create explosion
// particles, but it could be used by a SoundSystem to play an explosion
// sound, etc..
//
// Uses a fairly rudimentary 2D partition system, but performs reasonably well.
class CollisionSystem : public ex::System<CollisionSystem> {
  static const int PARTITIONS = 200;

  struct Candidate {
    sf::Vector2f position;
    float radius;
    ex::Entity entity;
  };

public:
  explicit CollisionSystem(sf::RenderTarget &target) : size(target.getSize()) {
    size.x = size.x / PARTITIONS + 1;
    size.y = size.y / PARTITIONS + 1;
  }

  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    reset();
    collect(es);
    collide(events);
  };

private:
  std::vector<std::vector<Candidate>> grid;
  sf::Vector2u size;

  void reset() {
    grid.clear();
    grid.resize(size.x * size.y);
  }

  void collect(ex::EntityManager &entities) {
    ex::ComponentHandle<Body> body;
    ex::ComponentHandle<Collideable> collideable;
    for (ex::Entity entity : entities.entities_with_components(body, collideable)) {
      unsigned int
          left = static_cast<int>(body->position.x - collideable->radius) / PARTITIONS,
          top = static_cast<int>(body->position.y - collideable->radius) / PARTITIONS,
          right = static_cast<int>(body->position.x + collideable->radius) / PARTITIONS,
          bottom = static_cast<int>(body->position.y + collideable->radius) / PARTITIONS;
        Candidate candidate {body->position, collideable->radius, entity};
        unsigned int slots[4] = {
          left + top * size.x,
          right + top * size.x,
          left  + bottom * size.x,
          right + bottom * size.x,
        };
        grid[slots[0]].push_back(candidate);
        if (slots[0] != slots[1]) grid[slots[1]].push_back(candidate);
        if (slots[1] != slots[2]) grid[slots[2]].push_back(candidate);
        if (slots[2] != slots[3]) grid[slots[3]].push_back(candidate);
    }
  }

  void collide(ex::EventManager &events) {
    for (const std::vector<Candidate> &candidates : grid) {
      for (const Candidate &left : candidates) {
        for (const Candidate &right : candidates) {
          if (left.entity == right.entity) continue;
          if (collided(left, right))
            events.emit<CollisionEvent>(left.entity, right.entity);
        }
      }
    }
  }

  float length(const sf::Vector2f &v) {
    return std::sqrt(v.x * v.x + v.y * v.y);
  }

  bool collided(const Candidate &left, const Candidate &right) {
    return length(left.position - right.position) < left.radius + right.radius;
  }
};


class ParticleSystem : public ex::System<ParticleSystem> {
public:
  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    ex::ComponentHandle<Particle> particle;
    for (ex::Entity entity : es.entities_with_components(particle)) {
      particle->alpha -= particle->d * dt;
      if (particle->alpha <= 0) {
        entity.destroy();
      } else {
        particle->colour.a = particle->alpha;
      }
    }
  }
};


class ParticleRenderSystem : public ex::System<ParticleRenderSystem> {
public:
  explicit ParticleRenderSystem(sf::RenderTarget &target) : target(target) {}

  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    sf::VertexArray vertices(sf::Quads);
    ex::ComponentHandle<Particle> particle;
    ex::ComponentHandle<Body> body;
    for (ex::Entity entity : es.entities_with_components(body, particle)) {
      float r = particle->radius;
      vertices.append(sf::Vertex(body->position + sf::Vector2f(-r, -r), particle->colour));
      vertices.append(sf::Vertex(body->position + sf::Vector2f(r, -r), particle->colour));
      vertices.append(sf::Vertex(body->position + sf::Vector2f(r, r), particle->colour));
      vertices.append(sf::Vertex(body->position + sf::Vector2f(-r, r), particle->colour));
    }
    target.draw(vertices);
  }
private:
  sf::RenderTarget &target;
};


// For any two colliding bodies, destroys the bodies and emits a bunch of bodgy explosion particles.
class ExplosionSystem : public ex::System<ExplosionSystem>, public ex::Receiver<ExplosionSystem> {
public:
  void configure(ex::EventManager &events) override {
    events.subscribe<CollisionEvent>(*this);
  }

  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    for (ex::Entity entity : collided) {
      emit_particles(es, entity);
      entity.destroy();
    }
    collided.clear();
  }

  void emit_particles(ex::EntityManager &es, ex::Entity entity) {
    ex::ComponentHandle<Body> body = entity.component<Body>();
    ex::ComponentHandle<Renderable> renderable = entity.component<Renderable>();
    ex::ComponentHandle<Collideable> collideable = entity.component<Collideable>();
    sf::Color colour = renderable->shape->getFillColor();
    colour.a = 200;

    float area = (M_PI * collideable->radius * collideable->radius) / 3.0;
    for (int i = 0; i < area; i++) {
      ex::Entity particle = es.create();

      float rotationd = r(720, 180);
      if (std::rand() % 2 == 0) rotationd = -rotationd;

      float offset = r(collideable->radius, 1);
      float angle = r(360) * M_PI / 180.0;
      particle.assign<Body>(
        body->position + sf::Vector2f(offset * cos(angle), offset * sin(angle)),
        body->direction + sf::Vector2f(offset * 2 * cos(angle), offset * 2 * sin(angle)),
        rotationd);

      float radius = r(3, 1);
      particle.assign<Particle>(colour, radius, radius / 2);
    }
  }

  void receive(const CollisionEvent &collision) {
    // Events are immutable, so we can't destroy the entities here. We defer
    // the work until the update loop.
    collided.insert(collision.left);
    collided.insert(collision.right);
  }

private:
  std::unordered_set<ex::Entity> collided;
};


// Render all Renderable entities and draw some informational text.
class RenderSystem  :public ex::System<RenderSystem> {
public:
  explicit RenderSystem(sf::RenderTarget &target, sf::Font &font) : target(target) {
    text.setFont(font);
    text.setPosition(sf::Vector2f(2, 2));
    text.setCharacterSize(18);
    text.setColor(sf::Color::White);
  }

  void update(ex::EntityManager &es, ex::EventManager &events, ex::TimeDelta dt) override {
    ex::ComponentHandle<Body> body;
    ex::ComponentHandle<Renderable> renderable;
    for (ex::Entity entity : es.entities_with_components(body, renderable)) {
      renderable->shape->setPosition(body->position);
      renderable->shape->setRotation(body->rotation);
      target.draw(*renderable->shape.get());
    }
    last_update += dt;
    frame_count++;
    if (last_update >= 0.5) {
      std::ostringstream out;
      const double fps = frame_count / last_update;
      out << es.size() << " entities (" << static_cast<int>(fps) << " fps)";
      text.setString(out.str());
      last_update = 0.0;
      frame_count = 0.0;
    }
    target.draw(text);
  }

private:
  double last_update = 0.0;
  double frame_count = 0.0;
  sf::RenderTarget &target;
  sf::Text text;
};
+/

class Application : EntitySysD!(64)
{
public:
    this(/*sf::RenderTarget &target, sf::Font &font*/)
    {
        /*systems.add<SpawnSystem>(target, 500);
        systems.add<BodySystem>();
        systems.add<BounceSystem>(target);
        systems.add<CollisionSystem>(target);
        systems.add<ExplosionSystem>();
        systems.add<ParticleSystem>();
        systems.add<RenderSystem>(target, font);
        systems.add<ParticleRenderSystem>(target);*/
        systems.configure();
    }

    void update(TimeDelta dt)
    {
        /*systems.update<SpawnSystem>(dt);
        systems.update<BodySystem>(dt);
        systems.update<BounceSystem>(dt);
        systems.update<CollisionSystem>(dt);
        systems.update<ExplosionSystem>(dt);
        systems.update<ParticleSystem>(dt);
        systems.update<RenderSystem>(dt);
        systems.update<ParticleRenderSystem>(dt);*/
    }
};



int main()
{
//  std::srand(std::time(nullptr));

  /*sf::RenderWindow window(sf::VideoMode::getDesktopMode(), "EntityX Example", sf::Style::Fullscreen);
  sf::Font font;
  if (!font.loadFromFile("LiberationSans-Regular.ttf")) {
    cerr << "error: failed to load LiberationSans-Regular.ttf" << endl;
    return 1;
  }*/

    auto app = new Application(/*window, font*/);

  //sf::Clock clock;
    //while (window.isOpen())
    {
        /*sf::Event event;
        while (window.pollEvent(event)) {
          switch (event.type) {
            case sf::Event::Closed:
            case sf::Event::KeyPressed:
              window.close();
              break;

            default:
              break;
          }
        }

        window.clear();
        sf::Time elapsed = clock.restart();*/
        app.update(0/*elapsed.asSeconds()*/);
        //window.display();
    }
}