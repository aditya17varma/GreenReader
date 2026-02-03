# GreenReader Physics and Computation

This document explains the mathematical models and algorithms used in GreenReader for terrain reconstruction and ball roll simulation.

## Table of Contents

1. [Coordinate System](#coordinate-system)
2. [Terrain Reconstruction](#terrain-reconstruction)
3. [Ball Roll Physics](#ball-roll-physics)
4. [Best Line Optimization](#best-line-optimization)

---

## Coordinate System

All computations use a local Cartesian coordinate system in **feet**:

| Axis | Direction | Positive |
|------|-----------|----------|
| **X** | East/West | +X = East |
| **Z** | North/South | +Z = North |
| **Y** | Elevation | +Y = Up |

The origin (0, 0) is at the center of the green.

---

## Terrain Reconstruction

### Overview

GreenReader reconstructs a 3D heightfield from hand-traced elevation contour lines using **Radial Basis Function (RBF) interpolation** with a thin-plate spline kernel.

### Input Data

1. **Boundary polygon**: Defines the green's perimeter in (X, Z) coordinates
2. **Contour lines**: Polylines at known elevations, traced from a contour map
3. **Contour interval**: Vertical spacing between contour lines (typically 0.25 ft)

### Algorithm

#### Step 1: Sample Contour Points

Each contour polyline is densified by sampling points at regular intervals (default: 1 ft):

```
For each segment (P₁, P₂) in the polyline:
    distance = |P₂ - P₁|
    n = max(1, floor(distance / step))
    For t in linspace(0, 1, n):
        sample = P₁ + t(P₂ - P₁)
```

This produces a set of constraint points `{(xᵢ, zᵢ, hᵢ)}` where `hᵢ` is the known elevation.

#### Step 2: RBF Interpolation

The elevation surface is modeled as:

$$Y(x, z) = \sum_{i=1}^{N} w_i \cdot \phi(r_i) + p(x, z)$$

Where:
- `rᵢ = ‖(x, z) - (xᵢ, zᵢ)‖` is the distance to sample point `i`
- `φ(r)` is the radial basis function
- `p(x, z)` is a polynomial term (for thin-plate splines: linear)
- `wᵢ` are weights solved from the constraint equations

**Thin-Plate Spline Kernel:**

$$\phi(r) = r^2 \ln(r)$$

This kernel minimizes the "bending energy" of the surface, producing smooth interpolation that passes through (or near) the constraint points.

**Smoothing Parameter:**

A smoothing factor (default: 0.1) controls the trade-off between:
- Exact interpolation through constraints (smooth = 0)
- Smoother surface that may deviate from constraints (smooth > 0)

#### Step 3: Grid Evaluation

The interpolated surface is evaluated on a regular grid:
- Resolution: typically 0.5 ft
- Grid dimensions: determined by the boundary bounding box
- Points outside the boundary polygon are masked (set to NaN)

#### Step 4: Normalization

The heightfield is shifted so the minimum elevation inside the green is 0 ft.

### Gradient Computation

Surface gradients are computed using central finite differences:

$$\frac{\partial Y}{\partial X} \approx \frac{Y_{i,j+1} - Y_{i,j-1}}{2 \cdot \Delta x}$$

$$\frac{\partial Y}{\partial Z} \approx \frac{Y_{i+1,j} - Y_{i-1,j}}{2 \cdot \Delta z}$$

The slope magnitude at each point:

$$\text{slope} = \sqrt{\left(\frac{\partial Y}{\partial X}\right)^2 + \left(\frac{\partial Y}{\partial Z}\right)^2}$$

---

## Ball Roll Physics

### Overview

The ball roll simulator models a golf ball rolling on the green surface using:
- **Gravity-induced acceleration** from surface slope
- **Rolling resistance** calibrated to Stimpmeter readings
- **Semi-implicit Euler integration** for numerical stability

### Stimpmeter Calibration

The [Stimpmeter](https://en.wikipedia.org/wiki/Stimpmeter) is a device used to measure green speed. A ball is released from a fixed ramp at a known exit velocity and the rollout distance is measured.

**Key relationship:**

On a flat, level surface, a ball launched at velocity `v₀` will decelerate uniformly and stop after rolling distance `d`:

$$d = \frac{v_0^2}{2a_0}$$

Solving for the deceleration:

$$a_0 = \frac{v_0^2}{2d}$$

**GreenReader parameters:**
- `v_stimp` = 6.0 ft/s (approximate Stimpmeter exit velocity)
- `stimp_ft` = user-specified Stimp reading (e.g., 10 ft)

Therefore:

$$a_0 = \frac{(6.0)^2}{2 \times \text{stimp\_ft}} = \frac{18}{\text{stimp\_ft}} \text{ ft/s}^2$$

For a 10-foot Stimp green: `a₀ = 1.8 ft/s²`

### Equations of Motion

The ball experiences two accelerations:

#### 1. Gravity on Slope

The component of gravity acting tangent to the surface:

$$\vec{a}_{\text{gravity}} = -g \cdot \nabla h = -g \cdot \left(\frac{\partial Y}{\partial X}, \frac{\partial Y}{\partial Z}\right)$$

Where `g = 32.174 ft/s²` is gravitational acceleration.

**Physical interpretation:** The ball accelerates downhill proportional to the slope. A 2% grade produces ~0.64 ft/s² acceleration.

#### 2. Rolling Resistance

Opposes the direction of motion with constant magnitude:

$$\vec{a}_{\text{resist}} = -a_0 \cdot \hat{v}$$

Where `v̂ = v / |v|` is the unit velocity vector.

#### Total Acceleration

$$\vec{a} = \vec{a}_{\text{gravity}} + \vec{a}_{\text{resist}}$$

Expanded:

$$a_x = -g \cdot \frac{\partial Y}{\partial X} - a_0 \cdot \frac{v_x}{|v|}$$

$$a_z = -g \cdot \frac{\partial Y}{\partial Z} - a_0 \cdot \frac{v_z}{|v|}$$

### Numerical Integration

**Semi-implicit Euler method** (symplectic, energy-preserving):

```
v(t + dt) = v(t) + a(t) · dt
p(t + dt) = p(t) + v(t + dt) · dt
```

Key difference from explicit Euler: position update uses the *new* velocity. This improves stability and reduces energy drift.

**Parameters:**
- Time step: `dt = 0.01 s`
- Maximum simulation time: 30 s
- Stop velocity threshold: 0.2 ft/s

### Hole Capture

The ball is considered "holed" when:
1. Distance to hole center ≤ cup radius (2.125 inches = 0.177 ft)
2. Speed ≤ capture threshold (4.0 ft/s)

This models realistic capture behavior—a ball moving too fast will lip out.

---

## Best Line Optimization

### Problem Statement

Given:
- Ball position `(ball_x, ball_z)`
- Hole position `(hole_x, hole_z)`
- Green surface (heightfield)
- Stimp reading

Find the optimal launch parameters `(angle_offset, speed)` that minimize miss distance.

### Search Space

The launch velocity is parameterized as:

$$v_x = \text{speed} \cdot \cos(\theta_{\text{base}} + \theta_{\text{offset}})$$

$$v_z = \text{speed} \cdot \sin(\theta_{\text{base}} + \theta_{\text{offset}})$$

Where:
- `θ_base = atan2(hole_z - ball_z, hole_x - ball_x)` is the direct aim angle
- `θ_offset` is the aim adjustment (positive = aim left of hole)
- `speed` is the launch speed in ft/s

**Search bounds:**
- Angle offset: ±25° from direct line
- Speed: 2–16 ft/s

### Scoring Function

Each candidate `(angle_offset, speed)` is evaluated by:

1. Running the ball roll simulation
2. Computing miss distance: `miss = |final_position - hole_position|`
3. Adding a blow-by penalty for non-holed balls: `penalty = 0.15 × final_speed`

$$\text{score} = \begin{cases}
-1000 - \text{miss} & \text{if holed} \\
\text{miss} + 0.15 \times v_{\text{final}} & \text{otherwise}
\end{cases}$$

The large negative score for holed putts ensures they're always preferred. The blow-by penalty discourages fast lines that "almost go in" but rocket past.

### Coarse-to-Fine Search

The optimization uses a 3-stage grid search that progressively refines around the best solution:

| Stage | Angle Step | Speed Step | Angle Window | Speed Window |
|-------|------------|------------|--------------|--------------|
| **1. Coarse** | 2.0° | 1.0 ft/s | ±25° | 2–16 ft/s |
| **2. Medium** | 0.5° | 0.25 ft/s | ±4° around best | ±2 ft/s around best |
| **3. Fine** | 0.2° | 0.1 ft/s | ±1° around best | ±0.6 ft/s around best |

**Stage 1 (Coarse):**
- Evaluates ~26 angles × 15 speeds = 390 simulations
- Finds approximate optimal region

**Stage 2 (Medium):**
- Evaluates ~17 angles × 17 speeds = 289 simulations
- Narrows to within 0.5° and 0.25 ft/s

**Stage 3 (Fine):**
- Evaluates ~11 angles × 13 speeds = 143 simulations
- Final precision: 0.2° angle, 0.1 ft/s speed

**Total:** ~822 ball roll simulations per best-line computation.

### Output

The optimization returns:
- `aimOffsetDeg`: Angle offset from direct aim (+ = left)
- `speedFps`: Launch speed
- `v0XFps`, `v0ZFps`: Velocity components
- `holed`: Whether the ball goes in
- `missFt`: Final distance from hole
- `tEndS`: Time until ball stops
- `pathXFt`, `pathZFt`, `pathYFt`: Full trajectory for visualization

---

## References

1. **Stimpmeter**: USGA specification for measuring green speed
2. **Thin-Plate Splines**: Duchon, J. (1977). "Splines minimizing rotation-invariant semi-norms in Sobolev spaces"
3. **RBF Interpolation**: SciPy `RBFInterpolator` documentation
4. **Golf Ball Physics**: Penner, A.R. (2002). "The physics of putting"
