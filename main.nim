import strformat
import std/math
import std/random

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
  IMAGE_SIZE = (width: 300, height: 300)
  NUM_SAMPLES = 10

type
  V = tuple[x: float, y: float, z: float]
  #
  Hit* = object
    at: V
    normal: V
    t: float
    material: Material
    valid: bool

  Material = tuple[color: Pixel]

  Sphere = object
    pos: V
    radius: float
    material: Material

  Ray = object
    origin: V
    direction: V

  World* = object
    spheres: seq[Sphere]
    skycolor: Pixel
    sundir: V
  #
  Pixel = V
  Image = array[IMAGE_SIZE.width, array[IMAGE_SIZE.height, Pixel]]

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

func v_prod(a: V, b: V): V =
  (a.x * b.x, a.y * b.y, a.z * b.z)

func v_length_sq(a: V): float =
  v_dot(a, a)

func v_length(a: V): float =
  sqrt(v_length_sq(a))

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
    normal = v_normalize(v_sub(sphere.pos, at))
    material = sphere.material
    valid = t > 0.0
  return Hit(at: at, normal: normal, t: t, material: material, valid: valid)


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
    jitter = v_scale(v_random_direction(), 1.0 / float(IMAGE_SIZE.width +
        IMAGE_SIZE.height))
    x = 2.0 * float(xi) / float(IMAGE_SIZE.width) - 1.0
    y = 2.0 * float(yi) / float(IMAGE_SIZE.height) - 1.0
    z = -1.0
  return make_ray(v_zero(), v_add((x, y, z), jitter))

func sample(ray: Ray, world: World): Pixel =
  var closest_hit = empty_hit()
  for s in world.spheres:
    let hit = ray_vs_sphere(ray, s)
    if hit.valid and hit.t < closest_hit.t or not closest_hit.valid:
      closest_hit = hit
  return if not closest_hit.valid:
    world.skycolor
  else:
    let l = clamp(v_dot(world.sundir, closest_hit.normal), 0.0, 1.0)
    v_scale(closest_hit.material.color, l)


proc main() =
  var
    image: Image

  let
    sphere = Sphere(pos: (1.0, 0.0, -5.0), radius: 2.0, material: (color: (
        1.0, 0.0, 0.0)))
    world = World(
        spheres: @[sphere],
        skycolor: (0.2, 0.2, 0.2),
        sundir: v_normalize((1.0, 1.0, -1.0)))

  echo "Rendering file"
  for xi in 0..IMAGE_SIZE.width-1:
    for yi in 0..IMAGE_SIZE.height-1:

      var
        current: Pixel
      for s in 0..NUM_SAMPLES-1:
        let ray = generate_ray(xi, yi)
        current = v_add(sample(ray, world), current)
      image[xi][yi] = v_scale(current, 1.0 / float(NUM_SAMPLES))

  echo "Writing file"
  write_image(image)


main()
