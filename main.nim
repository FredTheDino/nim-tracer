import strformat
import std/math

# Things to do
#  - Generate an image
#  - Write image to file
#  - Generate funky images?
#  - Ray plane intersection
#  - Ray sphere intersection
#  - Some shading! :D

const
  IMAGE_SIZE = (width: 256, height: 256)

type
  Vec = tuple[x: float, y: float, z: float]
  Pixel = tuple[r: float, g: float, b: float]
  Image = array[IMAGE_SIZE.width, array[IMAGE_SIZE.height, Pixel]] 

proc clamp*[T](a: T, lo: T, hi: T): T =
  if a < lo: return a
  elif hi < a: return hi
  else: return a

proc write_image(image: Image) =
  let f = open("output.ppm", fmWrite)
  defer: f.close()

  proc render_float(x: float): int =
    return clamp(int(x * 255.0), 0, 255)

  proc render_pixel(p: Pixel): string =
    fmt"{render_float(p.r)} {render_float(p.g)} {render_float(p.b)}"

  f.write "P3\n"
  f.write fmt"{IMAGE_SIZE.width} {IMAGE_SIZE.height}"
  f.write "\n"
  f.write "255\n"
  for r in image:
    for p in r:
      f.write render_pixel(p)
      f.write " "
    f.write "\n"



proc main() =
  var
    image: Image

  echo "Rendering file"
  for x in 0..IMAGE_SIZE.width-1:
    for y in 0..IMAGE_SIZE.height-1:
      image[x][y] = (r: 0.5, g: float(x) * 0.1 mod 1.0, b: float(y) * 0.2 mod 1.0)

  echo "Writing file"
  write_image(image)


main()
