import strformat
import std/math
import std/random

import macros

# https://stackoverflow.com/questions/47443206/how-to-debug-print-a-variable-name-and-its-value-in-nim#47443207
macro debug*(n: varargs[typed]): untyped =
  result = newNimNode(nnkStmtList, n)
  for i in 0..n.len-1:
    if n[i].kind == nnkStrLit:
      # pure string literals are written directly
      result.add(newCall("write", newIdentNode("stdout"), n[i]))
    else:
      # other expressions are written in <expression>: <value> syntax
      result.add(newCall("write", newIdentNode("stdout"), toStrLit(n[i])))
      result.add(newCall("write", newIdentNode("stdout"), newStrLitNode(": ")))
      result.add(newCall("write", newIdentNode("stdout"), n[i]))
    if i != n.len-1:
      # separate by ", "
      result.add(newCall("write", newIdentNode("stdout"), newStrLitNode(", ")))
    else:
      # add newline
      result.add(newCall("writeLine", newIdentNode("stdout"), newStrLitNode("")))

# Things to do
#  - [x] Generate an image
#  - [x] Write image to file
#  - [x] Generate funky images?
#  - Ray plane intersection
#  - [x] Ray sphere intersection
#  - BOUNCES!
#  - Some shading! :D
#  - Better color combining

const
  IMAGE_SIZE = (width: 300, height: 200)
  NUM_SAMPLES = 300

type
  V = tuple[x: float, y: float, z: float]
  #
  Hit* = object
    at: V
    normal: V
    t: float
    material: Material
    valid: bool

  Material = object
    color: Pixel
    roughness: float
    emitter: float

  Sphere = object
    pos: V
    radius: float
    material: Material

  Plane = object
    pos: V
    normal: V
    material: Material

  Ray = object
    origin: V
    direction: V

  World* = object
    spheres: seq[Sphere]
    planes: seq[Plane]
    skycolor: Pixel
  #
  Pixel = V
  Image = array[IMAGE_SIZE.height, array[IMAGE_SIZE.width, Pixel]]

# Vector
func v_unit(): V =
  (x: 1.0, y: 1.0, z: 1.0)

func v_zero(): V =
  (x: 0.0, y: 0.0, z: 0.0)

func v_add(a: V, b: V): V =
  (x: a.x + b.x, y: a.y + b.y, z: a.z + b.z)

func v_scale(a: V, f: float): V =
  (x: f * a.x, y: f * a.y, z: f * a.z)

func v_neg(a: V): V =
  v_scale(a, -1.0)

func v_sub(a: V, b: V): V =
  v_add(a, v_neg(b))

func v_dot(a: V, b: V): float =
  a.x * b.x + a.y * b.y + a.z * b.z

func v_mix(a: V, b: V, s: float): V =
  v_add(v_scale(a, 1.0 - s), v_scale(b, s))

func v_prod(a: V, b: V): V =
  (a.x * b.x, a.y * b.y, a.z * b.z)

func v_length_sq(a: V): float =
  v_dot(a, a)

func v_length(a: V): float =
  sqrt(v_length_sq(a))

func v_reflect(a: V, n: V): V =
  v_add(a, v_scale(n, v_dot(a, n) * -2.0))

func v_normalize(a: V): V =
  v_scale(a, 1.0 / v_length(a))

proc v_random(): V =
  let v = (x: rand(2.0) - 1.0, y: rand(2.0) - 1.0, z: rand(2.0) - 1.0)
  if v_length_sq(v) <= 1.0: v
  else: v_random()

proc v_random_direction(): V =
  let
    v = (x: rand(2.0) - 1.0, y: rand(2.0) - 1.0, z: rand(2.0) - 1.0)
    l = v_length(v)
  if l <= 1.0: v_scale(v, 1.0 / l)
  else: v_random_direction()

func empty_hit(): Hit =
  var
    hit: Hit
  hit.valid = false
  hit.t = 100000.0
  return hit

func make_ray(origin: V, direction: V): Ray =
  Ray(origin: origin, direction: v_normalize(direction))

func ray_vs_sphere(ray: Ray, sphere: Sphere): Hit =
  let
    oc = v_sub(ray.origin, sphere.pos)
    b = 2.0 * v_dot(oc, ray.direction)
    c = v_length_sq(oc) - sphere.radius * sphere.radius
    d = b * b - 4.0 * c
  if d < 0.0:
    return empty_hit()
  let
    t_a = (-b - sqrt(d)) / 2.0
    t_b = (-b + sqrt(d)) / 2.0
    t = if t_a > 0: t_a
        else: t_b
    at = v_add(ray.origin, v_scale(ray.direction, t))
    normal = v_normalize(v_sub(at, sphere.pos))
    material = sphere.material
    valid = t > 0.0
  return Hit(at: at, normal: normal, t: t, material: material, valid: valid)

proc ray_vs_plane(ray: Ray, plane: Plane): Hit =
  let
    op = v_sub(ray.origin, plane.pos)
    d = v_dot(op, plane.normal)
    t = 1.0 / v_dot(ray.direction, plane.normal) * d
  if t < 0.01:
    return empty_hit()
  let
    at = v_add(ray.origin, v_scale(ray.direction, t))
    normal = v_neg(plane.normal)
    material = plane.material
    valid = t > 0
  return Hit(at: at, normal: normal, t: t, material: material, valid: valid)

proc ray_bounce(ray: Ray, hit: Hit): Ray =
  let
    reflection = v_normalize(v_reflect(ray.direction, hit.normal))
    random_dir = v_random_direction()
    refraction = if v_dot(hit.normal, random_dir) > 0: random_dir
                 else: v_neg(random_dir)
    direction = v_normalize(v_mix(reflection, refraction,
        hit.material.roughness))
    origin = v_add(hit.at, v_scale(hit.normal, 0.00001))
  Ray(origin: origin, direction: direction)

# Math
func clamp*[T](a: T, lo: T, hi: T): T =
  if a < lo: lo
  elif hi < a: hi
  else: a

# Image
proc write_image(image: Image) =
  let f = open("output.ppm", fmWrite)
  defer: f.close()

  func render_float(x: float): int =
    clamp(int(x * 255.0), 0, 255)

  func render_pixel(p: Pixel): string =
    fmt"{render_float(p.x)} {render_float(p.y)} {render_float(p.z)}"

  f.write "P3\n"
  f.write fmt"{IMAGE_SIZE.width} {IMAGE_SIZE.height}"
  f.write "\n"
  f.write "255\n"
  for r in image:
    for p in r:
      f.write render_pixel(p)
      f.write "   "
    f.write "\n"

proc generate_ray(xi: int, yi: int): Ray =
  let
    t = rand(PI)
    w = 1.0 / float(IMAGE_SIZE.width + IMAGE_SIZE.height)
    jitter = v_scale((cos(t), sin(t), 0.0), w)
    #
    r = float(IMAGE_SIZE.width) / (float(IMAGE_SIZE.width) * float(
        IMAGE_SIZE.height))
    x = r * (float(xi) - (IMAGE_SIZE.width / 2))
    y = r * (float(yi) - (IMAGE_SIZE.height / 2))
    z = -1.0
  return make_ray(v_zero(), v_add((x, y, z), jitter))

proc sample(ray: Ray, world: World, bounces: int): Pixel =
  if bounces == 0:
    return v_zero()
  var closest_hit = empty_hit()
  #
  for s in world.spheres:
    let hit = ray_vs_sphere(ray, s)
    if hit.valid and hit.t < closest_hit.t:
      closest_hit = hit
  #
  for p in world.planes:
    let hit = ray_vs_plane(ray, p)
    if hit.valid and hit.t < closest_hit.t or not closest_hit.valid:
      closest_hit = hit
  #
  return if not closest_hit.valid:
    world.skycolor
  else:
    let
      hit = closest_hit
      next_ray = ray_bounce(ray, hit)
      next_sample = sample(next_ray, world, bounces - 1)
    v_mix(v_prod(v_scale(next_sample, 0.95), hit.material.color)
         , hit.material.color
         , hit.material.emitter
         )



proc main() =
  var
    image: Image

  let
    sphere = Sphere(
        pos: (-2.0, -0.4, -8.0),
        radius: 2.0,
        material: Material(roughness: 0.0, color: (1.0, 1.0, 0.0), emitter: 0.0))

    sun = Sphere(
        pos: (2.0, -0.4, -8.0),
        radius: 1.0,
        material: Material(roughness: 1.0, color: (10.0, 0.0, 10.0), emitter: 0.5))

    moon = Sphere(
        pos: (0.0, -20.0, -8.0),
        radius: 10.0,
        material: Material(roughness: 0.0, color: (5.0, 5.0, 5.0), emitter: 0.5))

    plane = Plane(
        pos: (0.0, -1.5, 0.0),
        normal: (0.0, 1.0, 0.0),
        material: Material(roughness: 1.0, color: (1.0, 1.0, 1.0), emitter: 0.0))
    world = World(
        spheres: @[sphere, sun, moon],
        planes: @[plane],
        skycolor: (0.0, 0.0, 0.0)
    )

  echo "Rendering file"
  for xi in 0..IMAGE_SIZE.width-1:
    for yi in 0..IMAGE_SIZE.height-1:

      var current: Pixel
      for s in 0..NUM_SAMPLES-1:
        let ray = generate_ray(xi, yi)
        current = v_add(sample(ray, world, 500), current)
      image[yi][xi] = v_scale(current, 1.0 / float(NUM_SAMPLES))

  echo "Writing file"
  write_image(image)


main()
