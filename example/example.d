import std.random;
import std.stdio;

import derelict.sdl2.sdl;

import entitysysd;


float r(int a, float b = 0)
{
    return cast(float)(uniform(0, a * 1000) + b * 1000) / 1000.0;
}

struct Vector2f
{
    float x, y;
}

struct Color
{
    ubyte r, g, b;
}


struct Body
{
    Vector2f position;
    Vector2f direction;
    float rotation = 0.0, rotationd;
}


struct Renderable
{
  /*explicit Renderable(std::unique_ptr<sf::Shape> shape) : shape(std::move(shape)) {}

  std::unique_ptr<sf::Shape> shape;*/
    float radius;
    Color color;
}


struct Particle
{
    Color color;
    float radius, alpha, d;
}


struct Collideable
{
    float radius;
}


// Emitted when two entities collide.
struct CollisionEvent
{
    Entity left, right;
}


class SpawnSystem : System
{
public:
    this(SDL_Window* window, int count)
    {
        SDL_GetWindowSize(window, &mSizeX, &mSizeY);
        mCount = count;
    }

    void update(EntityManager es, EventManager events, Duration dt)
    {
        int c = 0;
        //ComponentHandle<Collideable> collideable;
        foreach (Entity entity; es.entitiesWith!Collideable)
            c++;

        for (int i = 0; i < mCount - c; i++)
        {
            Entity entity = es.create();

            // Mark as collideable (explosion particles will not be collideable).
            //todo use "assign" to merge the 2 next instructions
            entity.insert!Collideable();
            entity.component!Collideable.radius = r(10, 5);
            //collideable = entity.assign<Collideable>(r(10, 5));

            // "Physical" attributes.
            entity.insert!Body();
            entity.component!Body.position  = Vector2f(r(mSizeX), r(mSizeY));
            entity.component!Body.direction = Vector2f(r(100, -50), r(100, -50));

            // Shape to apply to entity.
            entity.insert!Renderable();
            entity.component!Renderable.radius = entity.component!Collideable.radius;
            entity.component!Renderable.color = Color(cast(ubyte)r(128, 127),
                                                      cast(ubyte)r(128, 127),
                                                      cast(ubyte)r(128, 127));
        }
    }

private:
    int mSizeX, mSizeY;;
    int mCount;
};

/+
// Updates a body's position and rotation.
struct BodySystem : public System<BodySystem> {
  void update(EntityManager &es, EventManager &events, Duration dt) override {
    ComponentHandle<Body> body;
    for (Entity entity : es.entities_with_components(body)) {
      body->position += body->direction * static_cast<float>(dt);
      body->rotation += body->rotationd * dt;
    }
  };
};


// Bounce bodies off the edge of the screen.
class BounceSystem : public System<BounceSystem> {
public:
  explicit BounceSystem(sf::RenderTarget &target) : size(target.getSize()) {}

  void update(EntityManager &es, EventManager &events, Duration dt) override {
    ComponentHandle<Body> body;
    for (Entity entity : es.entities_with_components(body)) {
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
class CollisionSystem : public System<CollisionSystem> {
  static const int PARTITIONS = 200;

  struct Candidate {
    sf::Vector2f position;
    float radius;
    Entity entity;
  };

public:
  explicit CollisionSystem(sf::RenderTarget &target) : size(target.getSize()) {
    size.x = size.x / PARTITIONS + 1;
    size.y = size.y / PARTITIONS + 1;
  }

  void update(EntityManager &es, EventManager &events, Duration dt) override {
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

  void collect(EntityManager &entities) {
    ComponentHandle<Body> body;
    ComponentHandle<Collideable> collideable;
    for (Entity entity : entities.entities_with_components(body, collideable)) {
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

  void collide(EventManager &events) {
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


class ParticleSystem : public System<ParticleSystem> {
public:
  void update(EntityManager &es, EventManager &events, Duration dt) override {
    ComponentHandle<Particle> particle;
    for (Entity entity : es.entities_with_components(particle)) {
      particle->alpha -= particle->d * dt;
      if (particle->alpha <= 0) {
        entity.destroy();
      } else {
        particle->colour.a = particle->alpha;
      }
    }
  }
};


class ParticleRenderSystem : public System<ParticleRenderSystem> {
public:
  explicit ParticleRenderSystem(sf::RenderTarget &target) : target(target) {}

  void update(EntityManager &es, EventManager &events, Duration dt) override {
    sf::VertexArray vertices(sf::Quads);
    ComponentHandle<Particle> particle;
    ComponentHandle<Body> body;
    for (Entity entity : es.entities_with_components(body, particle)) {
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
class ExplosionSystem : public System<ExplosionSystem>, public Receiver<ExplosionSystem> {
public:
  void configure(EventManager &events) override {
    events.subscribe<CollisionEvent>(*this);
  }

  void update(EntityManager &es, EventManager &events, Duration dt) override {
    for (Entity entity : collided) {
      emit_particles(es, entity);
      entity.destroy();
    }
    collided.clear();
  }

  void emit_particles(EntityManager &es, Entity entity) {
    ComponentHandle<Body> body = entity.component<Body>();
    ComponentHandle<Renderable> renderable = entity.component<Renderable>();
    ComponentHandle<Collideable> collideable = entity.component<Collideable>();
    sf::Color colour = renderable->shape->getFillColor();
    colour.a = 200;

    float area = (M_PI * collideable->radius * collideable->radius) / 3.0;
    for (int i = 0; i < area; i++) {
      Entity particle = es.create();

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
  std::unordered_set<Entity> collided;
};
+/

// Render all Renderable entities
class RenderSystem : System
{
public:
    this(SDL_Renderer* renderer)
    {
        mpRenderer = renderer;
    }

    void update(EntityManager es, EventManager events, Duration dt)
    {
        foreach (Entity entity; es.entitiesWith!(Body, Renderable))
        {
            auto radius = entity.component!Renderable.radius;
            // Change color
            SDL_SetRenderDrawColor(mpRenderer,
                                   entity.component!Renderable.color.r,
                                   entity.component!Renderable.color.g,
                                   entity.component!Renderable.color.b,
                                   255 );
            SDL_Rect rect;
            rect.x = cast(int)(entity.component!Body.position.x - radius);
            rect.y = cast(int)(entity.component!Body.position.y - radius);
            rect.w = cast(int)(radius * 2);
            rect.h = cast(int)(radius * 2);
            SDL_RenderFillRect(mpRenderer, &rect);
        }
    }

private:
    SDL_Renderer* mpRenderer;
}


class Application : EntitySysD
{
public:
    this(SDL_Renderer* renderer, SDL_Window* window)
    {
        super();
        systems.insert(new SpawnSystem(window, 10));
        /*systems.add<BodySystem>();
        systems.add<BounceSystem>(target);
        systems.add<CollisionSystem>(target);
        systems.add<ExplosionSystem>();
        systems.add<ParticleSystem>();*/
        systems.insert(new RenderSystem(renderer));
        /*systems.add<ParticleRenderSystem>(target);*/
        //systems.configure();
    }

    void update(Duration dt)
    {
        systems.update(dt);
        /+
        systems.update<SpawnSystem>(dt);
        /*systems.update<BodySystem>(dt);
        systems.update<BounceSystem>(dt);
        systems.update<CollisionSystem>(dt);
        systems.update<ExplosionSystem>(dt);
        systems.update<ParticleSystem>(dt);*/
        systems.update<RenderSystem>(dt);
        /*systems.update<ParticleRenderSystem>(dt);*/
        +/
    }
};



void main()
{
    DerelictSDL2.load();
    scope(exit) DerelictSDL2.unload();

    if (SDL_Init(SDL_INIT_EVERYTHING) == -1)
        return;

    SDL_Window* window = SDL_CreateWindow("Server", 0, 0, 640, 480, 0);
    SDL_Renderer* renderer = SDL_CreateRenderer(window, -1, 0);
    SDL_RenderSetLogicalSize(renderer, 640, 480);

    auto app = new Application(renderer, window);

    bool loop = true;
    MonoTime timestamp = MonoTime.currTime;

    while (loop)
    {
        SDL_Event event;
        while (SDL_PollEvent(&event))
        {
            if (event.type == SDL_QUIT)
                loop = false;
        }

        SDL_SetRenderDrawColor(renderer, 255, 255, 255, 255 );
        SDL_RenderClear(renderer);

        app.update(dur!"msecs"(16));

        SDL_RenderPresent(renderer);

        MonoTime now = MonoTime.currTime;
        Duration timeElapsed = now - timestamp;
        long delay = 16 - timeElapsed.total!"msecs";
        if (delay < 0)
            delay = 0;

        // Add a 16msec delay to run at ~60 fps
        SDL_Delay(cast(uint)delay);
        timestamp = MonoTime.currTime;
    }
}