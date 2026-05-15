# D3-Force API Reference

Complete API documentation for d3-force module.

## Table of Contents
1. [Simulation](#simulation)
2. [Center Force](#center-force)
3. [Collide Force](#collide-force)
4. [Link Force](#link-force)
5. [Many-Body Force](#many-body-force)
6. [Position Forces](#position-forces)
7. [Custom Forces](#custom-forces)

---

## Simulation

### d3.forceSimulation([nodes])
Creates a new simulation with specified nodes array (default: empty).

**Warning**: Mutates passed nodes to assign `index`, `x`, `y`, `vx`, `vy`.

```javascript
const simulation = d3.forceSimulation(nodes);
```

### simulation.restart()
Restarts internal timer. Use to reheat after pause or during interaction.

### simulation.stop()
Stops internal timer. Use for manual stepping with `tick()`.

### simulation.tick([iterations])
Manually advance simulation by iterations (default: 1).
Does not dispatch events (use for static layouts).

```javascript
simulation.stop();
for (let i = 0; i < 300; i++) simulation.tick();
```

### simulation.nodes([nodes])
Get/set nodes array. Each node object receives:
- `index` - zero-based index
- `x`, `y` - position (initialized in phyllotaxis pattern if NaN)
- `vx`, `vy` - velocity (initialized to 0 if NaN)

**Fixed positions**: Set `fx`, `fy` to pin node; set to `null` to release.

### simulation.alpha([alpha])
Get/set current alpha [0,1]. Default: 1.
Alpha is like temperature in simulated annealing - decreases as simulation cools.

### simulation.alphaMin([min])
Get/set minimum alpha [0,1]. Default: 0.001.
Simulation stops when alpha < alphaMin.

### simulation.alphaDecay([decay])
Get/set alpha decay rate [0,1]. Default: 0.0228 (~300 iterations).
Higher = faster stabilization but may get stuck in local minimum.

### simulation.alphaTarget([target])
Get/set target alpha [0,1]. Default: 0.
Set > 0 to keep simulation running indefinitely.

### simulation.velocityDecay([decay])
Get/set velocity decay [0,1]. Default: 0.4.
Velocity multiplied by (1 - decay) each tick. Higher = more friction.

### simulation.force(name[, force])
Get/set force by name. Pass `null` to remove.

```javascript
simulation
  .force("charge", d3.forceManyBody())
  .force("center", d3.forceCenter(width/2, height/2));

simulation.force("charge", null); // Remove
```

### simulation.find(x, y[, radius])
Find closest node to position. Returns `undefined` if none within radius.

### simulation.randomSource([source])
Get/set random number generator (function returning [0,1)).
Default: fixed-seed LCG for deterministic layouts.

### simulation.on(typenames[, listener])
Add/remove event listeners. Types:
- `tick` - after each internal tick
- `end` - when alpha < alphaMin

```javascript
simulation.on("tick", () => renderNodes());
simulation.on("end", () => console.log("Simulation complete"));
```

---

## Center Force

Translates all nodes so center of mass is at target position.
Does not modify velocities (no oscillation).

### d3.forceCenter([x, y])
Create center force. Default position: ⟨0,0⟩.

```javascript
const center = d3.forceCenter(width / 2, height / 2);
```

### center.x([x])
Get/set x-coordinate. Default: 0.

### center.y([y])
Get/set y-coordinate. Default: 0.

### center.strength([strength])
Get/set strength [0,1]. Default: 1.
Lower values (e.g., 0.05) soften movements for dynamic graphs.

---

## Collide Force

Treats nodes as circles, prevents overlap via iterative relaxation.

### d3.forceCollide([radius])
Create collide force. Default radius: 1.

```javascript
const collide = d3.forceCollide(d => d.r);
```

### collide.radius([radius])
Get/set radius accessor (number or function).
Function receives (node, index).

### collide.strength([strength])
Get/set strength [0,1]. Default: 1.
Lower = softer constraint resolution.

### collide.iterations([iterations])
Get/set iterations per tick. Default: 1.
Higher = more rigid constraint, more computation.

---

## Link Force

Spring force pushing linked nodes toward target distance.

### d3.forceLink([links])
Create link force. Default: empty array.

**Warning**: Mutates links - replaces `source`/`target` identifiers with node references.

```javascript
const link = d3.forceLink(links).id(d => d.id);
```

### link.links([links])
Get/set links array. Each link has:
- `source` - source node (or identifier before init)
- `target` - target node (or identifier before init)
- `index` - zero-based index

### link.id([id])
Get/set node id accessor. Default: `d => d.index`.

```javascript
// Use string IDs
link.id(d => d.id);

// Links can then use string references
const links = [
  { source: "Alice", target: "Bob" }
];
```

### link.distance([distance])
Get/set target distance (number or function). Default: 30.
Function receives (link, index).

### link.strength([strength])
Get/set strength (number or function).
Default: `1 / Math.min(count(source), count(target))`
(reduces strength for heavily connected nodes).

### link.iterations([iterations])
Get/set iterations per tick. Default: 1.
Higher = more rigid links, useful for lattices.

---

## Many-Body Force

Global force between all nodes (attraction or repulsion).
Uses Barnes-Hut approximation: O(n log n).

### d3.forceManyBody()
Create many-body force.

```javascript
const charge = d3.forceManyBody().strength(-100);
```

### manyBody.strength([strength])
Get/set strength (number or function). Default: -30.
- Negative = repulsion (electrostatic)
- Positive = attraction (gravity)

### manyBody.theta([theta])
Get/set Barnes-Hut accuracy. Default: 0.9.
Higher = faster but less accurate (good for large graphs).

### manyBody.distanceMin([distance])
Get/set minimum distance. Default: 1.
Prevents infinite force when nodes coincide.

### manyBody.distanceMax([distance])
Get/set maximum distance. Default: Infinity.
Finite value improves performance, creates localized force.

---

## Position Forces

Push nodes toward target positions along one axis or radially.

### d3.forceX([x])
Create x-position force. Default target: 0.

```javascript
const forceX = d3.forceX(width / 2);
```

### x.x([x])
Get/set target x (number or function). Function receives (node, index).

### x.strength([strength])
Get/set strength [0,1]. Default: 0.1.
Node moves `(target - current) × strength` per tick.

### d3.forceY([y])
Create y-position force. Default target: 0.

### y.y([y])
Get/set target y (number or function).

### y.strength([strength])
Get/set strength [0,1]. Default: 0.1.

### d3.forceRadial(radius[, x, y])
Create radial force toward circle. Default center: ⟨0,0⟩.

```javascript
const radial = d3.forceRadial(100, width/2, height/2);
```

### radial.radius([radius])
Get/set circle radius (number or function).

### radial.x([x])
Get/set circle center x. Default: 0.

### radial.y([y])
Get/set circle center y. Default: 0.

### radial.strength([strength])
Get/set strength [0,1]. Default: 0.1.

---

## Custom Forces

A force is a function modifying node positions/velocities.

```javascript
function customForce(alpha) {
  for (const node of nodes) {
    // Modify node.vx, node.vy (or node.x, node.y)
    node.vx -= node.x * alpha * 0.1;
    node.vy -= node.y * alpha * 0.1;
  }
}

// With initialization
function boundingBox() {
  let nodes;
  
  function force(alpha) {
    for (const node of nodes) {
      if (node.x < 0) node.x = 0;
      if (node.x > width) node.x = width;
      if (node.y < 0) node.y = 0;
      if (node.y > height) node.y = height;
    }
  }
  
  force.initialize = function(_nodes) {
    nodes = _nodes;
  };
  
  return force;
}

simulation.force("bounds", boundingBox());
```

### force(alpha)
Apply force. Typically modify `node.vx`, `node.vy`.
May also directly modify `node.x`, `node.y` for constraints.

### force.initialize(nodes, random)
Called when force is bound to simulation or nodes change.
Store nodes reference for use in `force()`.
