## Dependency
Install [OpenGL::Modern](https://metacpan.org/pod/OpenGL::Modern), [Image::PNG::Const](https://metacpan.org/pod/Image::PNG::Const), and [Image::PNG::Libpng](https://metacpan.org/pod/Image::PNG::Libpng) using __cpan__:
```
cpan OpenGL::Modern Image::PNG::Const Image::PNG::Libpng
```
Install [GLM](https://github.com/kevinxie4c/GLM) and [Mocap-BVH](https://github.com/kevinxie4c/Mocap-BVH) following the instructions.

## Usage
```
perl viewer.pl [OPTION] MOTION_FILE [MOTION_FRAME_DATA] 
```
### Options
**--start start_frame**: which frame to start;

**--floory floor_y**: put the floory at _y=floor_y_;

**-g, --geo geomerty_file**: use _geometry_file_ for geometry configuration;

**--contact contact_file**: visualize contacts in _contact_file;

**--zmp zmp_file**: visualize ZMP in _zmp_file_;

**--sp support_polygon_file**: visualize support polygons in _support_polygon_file_;

**--extforce external_force_file**: visualize external forces in _external_force_file_;

**-w, --winsize wxh**: set the window size at _w_ by _h_;

**--floorsize wxh**: set the floor size at _w_ by _h_;

**--camera camera_file**: use _camera_file_ for camera configuration.
