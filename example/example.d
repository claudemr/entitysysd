import std.container;
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
}


struct Renderable
{
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
class CollisionEvent : Event!(CollisionEvent)
{
    this(Entity lA, Entity lB)
    {
        a = lA;
        b = lB;
    }
    Entity a, b;
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
            float radius = r(10, 5);
            entity.insert!Collideable();
            entity.component!Collideable.radius = radius;
            //collideable = entity.assign<Collideable>(r(10, 5));

            // "Physical" attributes.
            entity.insert!Body();
            entity.component!Body.position  = Vector2f(r(mSizeX), r(mSizeY));
            entity.component!Body.direction = Vector2f(r(300, -150),
                                                       r(300, -150));

            // Shape to apply to entity.
            entity.insert!Renderable();
            entity.component!Renderable.radius = radius;
            entity.component!Renderable.color = Color(cast(ubyte)r(128, 127),
                                                      cast(ubyte)r(128, 127),
                                                      cast(ubyte)r(128, 127));
        }
    }

private:
    int mSizeX, mSizeY;
    int mCount;
};


// Updates a body's position and rotation.
class MoveSystem : System
{
public:
    this(SDL_Window* window)
    {
        SDL_GetWindowSize(window, &mSizeX, &mSizeY);
    }

    void update(EntityManager es, EventManager events, Duration dt)
    {
        foreach (Entity entity; es.entitiesWith!Body)
        {
            Body *bod = entity.component!Body;

            // update position
            bod.position.x += bod.direction.x * dt.total!"msecs" / 1000.0;
            bod.position.y += bod.direction.y * dt.total!"msecs" / 1000.0;

            // make it bounce on the edges of the window
            if (bod.position.x < 0.0)
            {
                bod.position.x = -bod.position.x;
                bod.direction.x = -bod.direction.x;
            }
            else if (bod.position.x >= mSizeX)
            {
                bod.position.x = 2 * mSizeX - bod.position.x;
                bod.direction.x = -bod.direction.x;
            }

            if (bod.position.y < 0.0)
            {
                bod.position.y = -bod.position.y;
                bod.direction.y = -bod.direction.y;
            }
            else if (bod.position.y >= mSizeY)
            {
                bod.position.y = 2 * mSizeY - bod.position.y;
                bod.direction.y = -bod.direction.y;
            }
        }
    }
private:
    int mSizeX, mSizeY;
}


// Determines if two Collideable bodies have collided. If they have it emits a
// CollisionEvent. This is used by ExplosionSystem to create explosion
// particles, but it could be used by a SoundSystem to play an explosion
// sound, etc..
//
// Uses a fairly rudimentary 2D partition system, but performs reasonably well.
class CollisionSystem : System
{
public:
    this(SDL_Window* window)
    {
        SDL_GetWindowSize(window, &mSizeX, &mSizeY);
        mGrid.length = mSizeX * mSizeY;
    }

    void update(EntityManager es, EventManager events, Duration dt)
    {
        reset();
        collect(es);
        collide(events);
    };

private:
    enum int mPartitions = 200;

    struct Candidate
    {
        Vector2f position;
        float radius;
        Entity entity;
    };

    Candidate[][] mGrid;
    int mSizeX, mSizeY;

    void reset()
    {
        foreach (ref candidates; mGrid)
            candidates.length = 0;
    }

    void collect(EntityManager entities)
    {
        foreach (entity; entities.entitiesWith!(Body, Collideable))
        {
            Body*        bod = entity.component!Body;
            Collideable* col = entity.component!Collideable;

            auto left   = cast(int)(bod.position.x - col.radius) / mPartitions;
            auto top    = cast(int)(bod.position.y - col.radius) / mPartitions;
            auto right  = cast(int)(bod.position.x + col.radius) / mPartitions;
            auto bottom = cast(int)(bod.position.y + col.radius) / mPartitions;

            auto candidate = Candidate(bod.position, col.radius, entity);
            uint[4] slots = [left + top * mSizeX,     right + top * mSizeX,
                             left  + bottom * mSizeX, right + bottom * mSizeX];
            mGrid[slots[0]] ~= candidate;
            if (slots[0] != slots[1])
                mGrid[slots[1]] ~= candidate;
            if (slots[1] != slots[2])
                mGrid[slots[2]] ~= candidate;
            if (slots[2] != slots[3])
                mGrid[slots[3]] ~= candidate;
        }
    }

    void collide(EventManager events)
    {
        foreach (candidates; mGrid)
            foreach (ref candidateA; candidates)
                foreach (ref candidateB; candidates)
                {
                    if (candidateA.entity == candidateB.entity)
                        continue;
                    if (collided(candidateA, candidateB))
                        events.emit!CollisionEvent(candidateA.entity,
                                                   candidateB.entity);
            }
    }

    float length2(const ref Vector2f v)
    {
        return v.x * v.x + v.y * v.y;
    }

    bool collided(in ref Candidate a, in ref Candidate b)
    {
        auto ab = Vector2f(a.position.x - b.position.x,
                           a.position.y - b.position.y);
        float radius2 = a.radius + b.radius;
        radius2 *= radius2;
        return length2(ab) < radius2;
    }
}

/+
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

+/

// For any two colliding bodies, destroys the bodies and emits a bunch of bodgy explosion particles.
class ExplosionSystem : System, Receiver!CollisionEvent
{
public:
    this(EventManager events)
    {
        events.subscribe!CollisionEvent(this);
    }

    void update(EntityManager es, EventManager events, Duration dt)
    {
        foreach (entity; mCollisions)
        {
            // the same entity might be detected by collision several times
            if (!entity.valid)
                continue;
            //emit_particles(es, entity);
            entity.destroy();
        }
        while (!mCollisions.empty)
            mCollisions.removeFront();
    }

  /+void emit_particles(EntityManager &es, Entity entity) {
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
  }+/

    void receive(CollisionEvent collision)
    {
        // Events are immutable, so we can't destroy the entities here. We defer
        // the work until the update loop.
        mCollisions.insertFront(collision.a);
        mCollisions.insertFront(collision.b);
    }

private:
    SList!Entity mCollisions;
};

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
        systems.insert(new MoveSystem(window));
        systems.insert(new CollisionSystem(window));
        systems.insert(new ExplosionSystem(events));
        //systems.add<ParticleSystem>();
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