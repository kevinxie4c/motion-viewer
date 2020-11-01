#!/usr/bin/env perl
use Getopt::Long;
use OpenGL::Modern qw(:all);
use OpenGL::GLUT qw(:all);
use OpenGL::Array;
use GLM;
use Math::Trig;
use Image::PNG::Libpng ':all';
use Image::PNG::Const ':all';

use FindBin qw($Bin);
use lib $Bin;
use MotionViewer::Shader;
use MotionViewer::Buffer;
use MotionViewer::Camera;
use MotionViewer::BVH;
use MotionViewer::Compress qw(:all);
use strict;
use warnings;

my $win_id;
my ($screen_width, $screen_height) = (1280, 720);
my ($shader, $buffer, $camera);
my $bvh;
my $auto_center = 0;
my $loop = 0;
my ($round, $trial) = (1, 1);
my ($show_pose, $show_ref) = (1, 0);
my ($show_m, $show_o) = (1, 1);
my ($m_dir, $o_dir);
my $itr = 0;
my $start_frame = 0;
#my $start_frame = 43;
#my $start_frame = 57;
#my $start_frame = 12;
#my $start_frame = 1006;
my ($samples_m, $samples_o);
#my ($samples);

my $orange = GLM::Vec3->new(1.0, 0.5, 0.2);
my $red    = GLM::Vec3->new(1.0, 0.0, 0.0);
my $blue   = GLM::Vec3->new(0.0, 0.0, 1.0);
my $white  = GLM::Vec3->new(1.0, 1.0, 1.0);
my $green  = GLM::Vec3->new(0.0, 1.0, 0.0);

my $alpha = 1;
my $num_of_samples = 20;
my $chr_dist = 0;
my $dist_idx = 2;

my $animate = 0;
my $fps = 10; # 0.1 second per iteration. 10 Hz.
my $ffmpeg = $^O eq 'MSWin32' ? 'ffmpeg.exe': 'ffmpeg';
my $fh_ffmpeg;
my $recording = 0;
my $png_counter = 0;

my $floor_y = 0;
#my $floor_y = 6.978;
#my $floor_y = -0.257;
my $floor_half_width = 10000;
my $floor_buffer;
my $cube_buffer;
my ($sphere_buffer, $num_vertices_sphere);
my ($cylinder_buffer, $num_vertices_cylinder);
my ($cone_buffer, $num_vertices_cone);

my $shadow_map_shader;
my ($shadow_map_height, $shadow_map_width) = (4096, 4096);
my ($shadow_map_buffer, $shadow_map_texture);
my $light_space_matrix;
my ($light_near, $light_far) = (1, 1000);

my $geometry_file;
my $contact_force_file;
my $zmp_file;
my $support_polygon_file;
my $ext_force_file;

my $primitive_shader;

GetOptions('mass=s'     => \$m_dir,
           'origin=s'   => \$o_dir,
           'start=i'    => \$start_frame,
           'floory=f'   => \$floor_y,
           'geo=s'      => \$geometry_file,
           'contact=s'  => \$contact_force_file,
           'zmp=s'      => \$zmp_file,
           'sp=s'       => \$support_polygon_file,
           'extforce=s' => \$ext_force_file,
);

die "need specifying bvh filename\n" unless @ARGV;
my $bvh_file = shift @ARGV;
my $frame = $start_frame;

my @motions;
for my $file (@ARGV) {
    open my $fh, '<', $file;
    while (<$fh>) {
        push @motions, [split];
    }
    close $fh;
}

my @contact_forces;
if ($contact_force_file) {
    open my $fh, '<', $contact_force_file;
    while (<$fh>) {
        my @a = split;
        for (my $i = 3; $i < @a; $i += 6) {
            for my $j(0..2) {
                $a[$i + $j - 3] *= 100;
                $a[$i + $j] = $a[$i + $j - 3] + $a[$i + $j] / 10;
            }
        }
        push @contact_forces, \@a;
    }
}

my @zmps;
if ($zmp_file) {
    open my $fh, '<', $zmp_file;
    while (<$fh>) {
        push @zmps, [map($_ * 100, split)];
    }
}

my @support_polygons;
if ($support_polygon_file) {
    open my $fh, '<', $support_polygon_file;
    while (<$fh>) {
        push @support_polygons, [map($_ * 100, split)];
    }
}

my @ext_forces;
if ($ext_force_file) {
    open my $fh, '<', $ext_force_file;
    while (<$fh>) {
        my @a = split;
        push @ext_forces, {
            node_name => $a[0],
            start_time => $a[1],
            duration => $a[2],
            force => [@a[3..5]],
        };
    }
}

my $identity_mat = GLM::Mat4->new(
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
);


sub load_sample {
    if ($m_dir) {
        my $trial_dir_m = File::Spec->catdir($m_dir, $round, $trial);
        if (-d $trial_dir_m) {
            print "mass:   round=$round, trial = $trial\n";
            $samples_m = decompress $trial_dir_m;
        } else {
            warn "cannot open $trial_dir_m";
        }
    }
    if ($o_dir) {
        my $trial_dir_o = File::Spec->catdir($o_dir, $round, $trial);
        if (-d $trial_dir_o) {
            print "origin: round=$round, trial = $trial\n";
            $samples_o = decompress $trial_dir_o;
        } else {
            warn "cannot open $trial_dir_o";
        }
    }
}

$num_of_samples = 1 if $m_dir eq '' && $o_dir eq '';

# a     d
#  +---+
#  |\  |
#  | \ |
#  |  \|
#  +---+
# b     c
sub create_floor {
    my @n = (0, 1, 0);
    my @a = (-$floor_half_width, $floor_y, -$floor_half_width);
    my @b = (-$floor_half_width, $floor_y,  $floor_half_width);
    my @c = ( $floor_half_width, $floor_y,  $floor_half_width);
    my @d = ( $floor_half_width, $floor_y, -$floor_half_width);
    $floor_buffer = MotionViewer::Buffer->new(2, @a, @n, @b, @n, @c, @n, @a, @n, @c, @n, @d, @n);
}

#   a                e
#    +--------------+
#    |\              \
#    | \ d            \ h
#    |  +--------------+
#    |  |              |
#    +  |           +  |
#   b \ |          f   |
#      \|              |
#       +--------------+
#      c                g
sub create_cube {
    my (@a, @b, @c, @d, @e, @f, @g, @h);
    @a = (-0.5,  0.5, -0.5);
    @b = (-0.5, -0.5, -0.5);
    @c = (-0.5, -0.5,  0.5);
    @d = (-0.5,  0.5,  0.5);
    @e = ( 0.5,  0.5, -0.5);
    @f = ( 0.5, -0.5, -0.5);
    @g = ( 0.5, -0.5,  0.5);
    @h = ( 0.5,  0.5,  0.5);

    my @vertices;
    my @n1 = (-1, 0, 0);
    push @vertices, @a, @n1, @b, @n1, @c, @n1;
    push @vertices, @c, @n1, @d, @n1, @a, @n1;

    my @n2 = (1, 0, 0);
    push @vertices, @g, @n2, @f, @n2, @e, @n2;
    push @vertices, @e, @n2, @h, @n2, @g, @n2;

    my @n3 = (0, 0, 1);
    push @vertices, @d, @n3, @c, @n3, @g, @n3;
    push @vertices, @g, @n3, @h, @n3, @d, @n3;

    my @n4 = (0, 0, -1);
    push @vertices, @f, @n4, @b, @n4, @a, @n4;
    push @vertices, @a, @n4, @e, @n4, @f, @n4;

    my @n5 = (0, 1, 0);
    push @vertices, @a, @n5, @d, @n5, @h, @n5;
    push @vertices, @h, @n5, @e, @n5, @a, @n5;

    my @n6 = (0, -1, 0);
    push @vertices, @g, @n6, @c, @n6, @b, @n6;
    push @vertices, @b, @n6, @f, @n6, @g, @n6;

    $cube_buffer = MotionViewer::Buffer->new(2, @vertices);
}

sub create_sphere {
    my ($xo, $yo, $zo, $r, $s) = (0, 0, 0, 3, 20); # x, y, z, radius, slice
    my @vlist;
    for (my $i = 0; $i < $s; ++$i) {
        my $theta1 = pi / $s * $i;
        my $theta2 = pi / $s * ($i + 1);
        my $y1 = cos($theta1);
        my $y2 = cos($theta2);
        my $r1 = sin($theta1);
        my $r2 = sin($theta2);
        for (my $j = 0; $j < $s * 2; ++$j) {
            my $phi1 = pi / $s * $j;
            my $phi2 = pi / $s * ($j + 1);
            my $za = $r1 * cos($phi1);
            my $xa = $r1 * sin($phi1);
            my $zb = $r2 * cos($phi1);
            my $xb = $r2 * sin($phi1);
            my $zc = $r2 * cos($phi2);
            my $xc = $r2 * sin($phi2);
            my $zd = $r1 * cos($phi2);
            my $xd = $r1 * sin($phi2);
            my ($a, $b, $c, $d);
            my ($na, $nb, $nc, $nd);
            $na = GLM::Vec3->new($xa, $y1, $za);
            $nb = GLM::Vec3->new($xb, $y2, $zb);
            $nc = GLM::Vec3->new($xc, $y2, $zc);
            $nd = GLM::Vec3->new($xd, $y1, $zd);
            $a = $na * $r;
            $b = $nb * $r;
            $c = $nc * $r;
            $d = $nd * $r;
            my $o = GLM::Vec3->new($xo, $yo, $zo);
            $a += $o;
            $b += $o;
            $c += $o;
            $d += $o;
            $a = GLM::Vec4->new($a->x, $a->y, $a->z, 1);
            $b = GLM::Vec4->new($b->x, $b->y, $b->z, 1);
            $c = GLM::Vec4->new($c->x, $c->y, $c->z, 1);
            $d = GLM::Vec4->new($d->x, $d->y, $d->z, 1);
            $na = GLM::Vec4->new($na->x, $na->y, $na->z, 0);
            $nb = GLM::Vec4->new($nb->x, $nb->y, $nb->z, 0);
            $nc = GLM::Vec4->new($nc->x, $nc->y, $nc->z, 0);
            $nd = GLM::Vec4->new($nd->x, $nd->y, $nd->z, 0);
            push @vlist, $a, $na;
            push @vlist, $b, $nb;
            push @vlist, $c, $nc;
            push @vlist, $c, $nc;
            push @vlist, $d, $nd;
            push @vlist, $a, $na;
        }
    }
    my @vertices = map { ($_->x, $_->y, $_->z) } @vlist;
    $num_vertices_sphere = @vertices / (3 * 2);
    $sphere_buffer = MotionViewer::Buffer->new(2, @vertices);
}

sub create_cylinder {
    my ($r, $h, $s) = (1, 1, 20); # radius, half height, slice
    my @vlist;
    for (my $i = 0; $i < $s; ++$i) {
        my $theta1 = 2 * pi / $s * $i;
        my $theta2 = 2 * pi / $s * ($i + 1);
        my $x1 = sin($theta1);
        my $x2 = sin($theta2);
        my $y1 = cos($theta1);
        my $y2 = cos($theta2);
        my $n1 = GLM::Vec3->new($x1, $y1, 0);
        my $n2 = GLM::Vec3->new($x2, $y2, 0);
        my $a = GLM::Vec3->new($x1 * $r, $y1 * $r,  $h);
        my $b = GLM::Vec3->new($x1 * $r, $y1 * $r, -$h);
        my $c = GLM::Vec3->new($x2 * $r, $y2 * $r, -$h);
        my $d = GLM::Vec3->new($x2 * $r, $y2 * $r,  $h);
        push @vlist, $a, $n1;
        push @vlist, $b, $n1;
        push @vlist, $c, $n2;
        push @vlist, $c, $n2;
        push @vlist, $d, $n2;
        push @vlist, $a, $n1;
    }
    my @vertices = map { ($_->x, $_->y, $_->z) } @vlist;
    $num_vertices_cylinder = @vertices / (3 * 2);
    $cylinder_buffer = MotionViewer::Buffer->new(2, @vertices);
}

sub create_cone {
    my ($r, $h, $s) = (1, 1, 20); # radius, height, slice
    my @vlist;
    for (my $i = 0; $i < $s; ++$i) {
        my $theta1 = 2 * pi / $s * $i;
        my $theta2 = 2 * pi / $s * ($i + 1);
        my $x1 = sin($theta1);
        my $x2 = sin($theta2);
        my $y1 = cos($theta1);
        my $y2 = cos($theta2);
        my $v1 = GLM::Vec3->new($x1, $y1, 0)->normalized;
        my $v2 = GLM::Vec3->new($x2, $y2, 0)->normalized;
        my $u = GLM::Vec3->new(0, 0, 1);
        my $n1 = ($h * $v1 + $r * $u)->normalized;
        my $n2 = ($h * $v2 + $r * $u)->normalized;
        my $n3 = (($n1 + $n2) / 2)->normalized;
        my $a = GLM::Vec3->new($x1 * $r, $y1 * $r,  0);
        my $b = GLM::Vec3->new($x2 * $r, $y2 * $r,  0);
        my $c = GLM::Vec3->new(       0,        0, $h);
        push @vlist, $a, $n1;
        push @vlist, $b, $n2;
        push @vlist, $c, $n3;
    }
    my @vertices = map { ($_->x, $_->y, $_->z) } @vlist;
    $num_vertices_cone = @vertices / (3 * 2);
    $cone_buffer = MotionViewer::Buffer->new(2, @vertices);
}

sub draw_floor {
    $floor_buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, 6);
}

sub draw_cube {
    die "usage: draw_cube(x, y, z)" if @_ < 3;
    my $translate = GLM::Functions::translate($identity_mat, GLM::Vec3->new(@_));
    $shader->set_mat4('model', $translate);
    $cube_buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, 36);
}

sub draw_sphere {
    die "usage: draw_sphere(x, y, z)" if @_ < 3;
    my $translate = GLM::Functions::translate($identity_mat, GLM::Vec3->new(@_));
    $shader->set_mat4('model', $translate);
    $sphere_buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, $num_vertices_sphere);
}

sub draw_cylinder {
    die "usage: draw_cylinder(x1, y1, z1, x2, y2, z2, r)" if @_ < 7;
    my ($x1, $y1, $z1, $x2, $y2, $z2, $r) = @_;
    my $a = GLM::Vec3->new($x1, $y1, $z1);
    my $b = GLM::Vec3->new($x2, $y2, $z2);
    my $v = $b - $a;
    my $scale = GLM::Functions::scale($identity_mat, GLM::Vec3->new($r, $r, $v->length / 2));
    my $rotate;
    if (abs($v->x) < 1e-6 && abs($v->y) < 1e-6) {
        $rotate = $identity_mat;
    } else {
        $v->normalize;
        my $u = GLM::Vec3->new(0, 0, 1);
        my $axis = $u->cross($v)->normalize;
        my $angle = acos($u->dot($v));
        $rotate = GLM::Functions::rotate($identity_mat, $angle, $axis);
    }
    my $translate = GLM::Functions::translate($identity_mat, ($a + $b) / 2);
    #print "$translate\n$rotate\n$scale\n";
    $shader->set_mat4('model', $translate * $rotate * $scale);
    $cylinder_buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, $num_vertices_cylinder);
}

sub draw_cone {
    die "usage: draw_cone(x1, y1, z1, x2, y2, z2, r)" if @_ < 7;
    my ($x1, $y1, $z1, $x2, $y2, $z2, $r) = @_;
    my $a = GLM::Vec3->new($x1, $y1, $z1);
    my $b = GLM::Vec3->new($x2, $y2, $z2);
    my $v = $b - $a;
    my $scale = GLM::Functions::scale($identity_mat, GLM::Vec3->new($r, $r, $v->length));
    my $rotate;
    if (abs($v->x) < 1e-6 && abs($v->y) < 1e-6) {
        $rotate = $identity_mat;
    } else {
        $v->normalize;
        my $u = GLM::Vec3->new(0, 0, 1);
        my $axis = $u->cross($v)->normalize;
        my $angle = acos($u->dot($v));
        $rotate = GLM::Functions::rotate($identity_mat, $angle, $axis);
    }
    my $translate = GLM::Functions::translate($identity_mat, $a);
    #print "$translate\n$rotate\n$scale\n";
    $shader->set_mat4('model', $translate * $rotate * $scale);
    $cone_buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, $num_vertices_cone);
}

sub draw_axis {
    die "usage: draw_cone(x1, y1, z1, x2, y2, z2)" if @_ < 6;
    my ($x1, $y1, $z1, $x2, $y2, $z2) = @_;
    my ($r1, $r2, $h) = (1, 2, 6);
    my $a = GLM::Vec3->new($x1, $y1, $z1);
    my $b = GLM::Vec3->new($x2, $y2, $z2);
    my $v = ($b - $a)->normalized;
    my $c = $b + 6 * $v;
    draw_cylinder($a->x, $a->y, $a->z, $b->x, $b->y, $b->z, $r1);
    draw_cone($b->x, $b->y, $b->z, $c->x, $c->y, $c->z, $r2);
}

sub draw_lines {
    my $line_buffer = MotionViewer::Buffer->new(1, @_);
    $line_buffer->bind;
    glDrawArrays(GL_LINES, 0, @_ / 3);
}

sub draw_support_polygon {
    my @vertices;
    my $ax = shift @_;
    my $offset = 0.1;
    my $ay = $floor_y + $offset;
    my $az = shift @_;
    my $bx = shift @_;
    my $by = $floor_y + $offset;
    my $bz = shift @_;
    my @n = (0, 1, 0);
    while (@_) {
        my $cx = shift @_;
        my $cy = $floor_y + $offset;
        my $cz = shift @_;
        push @vertices, $ax, $ay, $az, @n;
        push @vertices, $bx, $by, $bz, @n;
        push @vertices, $cx, $cy, $cz, @n;
        ($bx, $by, $bz) = ($cx, $cy, $cz);
    }
    $shader->set_mat4('model', $identity_mat);
    my $buffer = MotionViewer::Buffer->new(2, @vertices);
    $buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, @vertices / 6);
}

sub init_shadow_map {
    my $buffer_array = OpenGL::Array->new(1, GL_INT);
    glGenFramebuffers_c(1, $buffer_array->ptr);
    $shadow_map_buffer = ($buffer_array->retrieve(0, 1))[0];
    my $texture_array = OpenGL::Array->new(1, GL_INT);
    glGenTextures_c(1, $texture_array->ptr);
    $shadow_map_texture = ($texture_array->retrieve(0, 1))[0];
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, $shadow_map_texture);
    glTexImage2D_c(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT, $shadow_map_width, $shadow_map_height, 0, GL_DEPTH_COMPONENT, GL_FLOAT, 0);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    glBindFramebuffer(GL_FRAMEBUFFER, $shadow_map_buffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, $shadow_map_texture, 0);
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

sub create_shadow_map {
    my $i = shift;
    my $light_proj = GLM::Functions::ortho(-500, 500, -500, 500, $light_near, $light_far);
    #my $light_view = GLM::Functions::lookAt(GLM::Vec3->new(200), GLM::Vec3->new(0), GLM::Vec3->new(0, 1, 0));
    my $light_view = GLM::Functions::lookAt($camera->center + GLM::Vec3->new(200), $camera->center, GLM::Vec3->new(0, 1, 0));
    $light_space_matrix = $light_proj * $light_view;
    $shadow_map_shader->use;
    $shadow_map_shader->set_mat4('lightSpaceMatrix', $light_space_matrix);
    glViewport(0, 0, $shadow_map_width, $shadow_map_height);
    glBindFramebuffer(GL_FRAMEBUFFER, $shadow_map_buffer);
    glClear(GL_DEPTH_BUFFER_BIT);

    $shadow_map_shader->set_mat4('model', $identity_mat);
    draw_floor;
    $bvh->shader($shadow_map_shader);
    my @tmp = $bvh->at_frame($frame);
    $tmp[$dist_idx] -= $chr_dist;
    $bvh->set_position(@tmp);

    #$bvh->set_position($bvh->at_frame($frame));
    $bvh->draw;
    if ($show_m && $samples_m) {
        $_ = $samples_m->[$itr][$i];
        if ($show_pose) {
            $bvh->set_position(@{$_->{pos}});
            $bvh->draw;
        }
        if ($show_ref) {
            $bvh->set_position(@{$_->{ref}});
            $bvh->draw;
        }
    }
    if ($show_o && $samples_o) {
        $_ = $samples_o->[$itr][$i];
        if ($show_pose) {
            my @tmp = @{$_->{pos}};
            $tmp[$dist_idx] += $chr_dist;
            $bvh->set_position(@tmp);

            #$bvh->set_position(@{$_->{pos}});
            $bvh->draw;
        }
        if ($show_ref) {
            my @tmp = @{$_->{ref}};
            $tmp[$dist_idx] += $chr_dist;
            $bvh->set_position(@tmp);

            #$bvh->set_position(@{$_->{ref}});
            $bvh->draw;
        }
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

sub destroy_shadow_map {
}

sub render {
    if ($auto_center) {
        my ($x, $y, $z) = $bvh->at_frame($frame); # Assume that the first 3 dofs are translation
        $camera->center(GLM::Vec3->new($x, $y, $z));
        $camera->update_view_matrix;
    }

    glClear(GL_ACCUM_BUFFER_BIT);
    glReadBuffer(GL_BACK); # We want to accumulate the back buffer. Some codes elsewhere might call glReadBuffer(GL_FRONT). Set it back here!
    for (my $i  = 0; $i < $num_of_samples; ++$i) {
        #glClearColor(0.0, 0.0, 0.0, 0.0);
        glClearColor(0.529, 0.808, 0.922, 0.0);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        #$shader->use;
        #$buffer->bind;
        #glDrawArrays(GL_TRIANGLES, 0, 3);
        glEnable(GL_DEPTH_TEST);

        create_shadow_map($i);

        glViewport(0, 0, $screen_width, $screen_height);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, $shadow_map_texture);

        #$primitive_shader->use;
        #$primitive_shader->set_mat4('view', $camera->view_matrix);
        #$primitive_shader->set_mat4('proj', $camera->proj_matrix);
        #$primitive_shader->set_mat4('model', $identity_mat);
        #$primitive_shader->set_vec3('color', $red);
        #draw_lines(0, 0, 0, 20, 0, 0);
        #$primitive_shader->set_vec3('color', $green);
        #draw_lines(0, 0, 0, 0, 20, 0);
        #$primitive_shader->set_vec3('color', $blue);
        #draw_lines(0, 0, 0, 0, 0, 20);
        
        $shader->use;
        $shader->set_mat4('lightSpaceMatrix', $light_space_matrix);
        #print "$light_space_matrix\n";
        $shader->set_mat4('view', $camera->view_matrix);
        $shader->set_mat4('proj', $camera->proj_matrix);

        $shader->set_float('alpha', 1.0);
        $shader->set_vec3('color', $white);
        $shader->set_mat4('model', $identity_mat);
        $shader->set_int('enableShadow', 1);
        draw_floor;
        $shader->set_int('enableShadow', 0);

        $shader->set_vec3('color', $orange);

        $bvh->shader($shader);
        my @tmp = $bvh->at_frame($frame);
        $tmp[$dist_idx] -= $chr_dist;
        $bvh->set_position(@tmp);

        #$bvh->set_position($bvh->at_frame($frame));
        $bvh->draw;

        for (my $j = 0; $j < 20; ++$j) {
            if (0 <= $frame - $j && $frame - $j < @zmps && @{$zmps[$frame - $j]} == 2) {
                $shader->set_float('alpha', 0.9 ** $j);
                $shader->set_vec3('color', $red);
                draw_sphere($zmps[$frame - $j][0], $floor_y, $zmps[$frame - $j][1]);
            }
        }

        if ($frame < @support_polygons && @{$support_polygons[$frame]} >= 6) {
            $shader->set_float('alpha', 1.0);
            $shader->set_vec3('color', $green);
            draw_support_polygon(@{$support_polygons[$frame]});
        }


        $bvh->update_transform;
        $shader->set_vec3('color', $blue);
        for (@ext_forces) {
            if ($_->{start_time} <= 0.01 * $frame && 0.01 * $frame <= $_->{start_time} + $_->{duration}) {
                my $joint = $bvh->joint($_->{node_name});
                #print "$joint\n";
                #print $joint->name, "\n";
                my $transform = $joint->{transform};
                #print $joint->{transform}, "\n";
                my $p1 = $transform * GLM::Vec4->new(0, 0, 0, 1);
                my $p2 = $p1 + GLM::Vec4->new(@{$_->{force}}, 0);
                #print "$p1 $p2\n";
                draw_axis($p1->x, $p1->y, $p1->z, $p2->x, $p2->y, $p2->z);
            }
        }
        $shader->use;

        glDisable(GL_DEPTH_TEST);
        $shader->set_float('alpha', $alpha);
        if ($show_m && $samples_m) {
            $_ = $samples_m->[$itr][$i];
            if ($show_pose) {
                $shader->set_vec3('color', $blue);
                $bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                $shader->set_vec3('color', 0.7 * $blue);
                $bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
            #$shader->set_vec3('color', $green);
            #draw_cube(map $_ * 100, @{$_->{zmp}});
        }
        if ($show_o && $samples_o) {
            $_ = $samples_o->[$itr][$i];
            if ($show_pose) {
                $shader->set_vec3('color', $red);

                my @tmp = @{$_->{pos}};
                $tmp[$dist_idx] += $chr_dist;
                $bvh->set_position(@tmp);

                #$bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                $shader->set_vec3('color', 0.7 * $red);
                
                my @tmp = @{$_->{ref}};
                $tmp[$dist_idx] += $chr_dist;
                $bvh->set_position(@tmp);

                #$bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
        }
        if ($frame < @contact_forces) {
            $primitive_shader->use;
            $primitive_shader->set_mat4('view', $camera->view_matrix);
            $primitive_shader->set_mat4('proj', $camera->proj_matrix);
            $primitive_shader->set_mat4('model', $identity_mat);
            $primitive_shader->set_vec3('color', $green);
            draw_lines(@{$contact_forces[$frame]});
        }
        glAccum(GL_ACCUM, 1.0 / $num_of_samples);
    }
    glAccum(GL_RETURN, 1);
    glutSwapBuffers();
    if ($recording) {
        my $buffer = OpenGL::Array->new($screen_width * $screen_height * 4, GL_BYTE);
        glReadBuffer(GL_FRONT);
        glReadPixels_c(0, 0, $screen_width, $screen_height, GL_RGBA, GL_UNSIGNED_BYTE, $buffer->ptr);
        print $fh_ffmpeg $buffer->retrieve_data(0, $screen_width * $screen_height * 4);
    }
}

sub timer {
    if ($animate) {
        if ($frame + 10 < $bvh->frames && (!defined($samples_m) || $itr + 1 < @$samples_m) && (!defined($samples_o) || $itr + 1 < @$samples_o)) {
        #if ($frame + 10 < $bvh->frames && $itr + 1 < @$samples) {
            $frame += 10;
            ++$itr;
        } else {
            if ($loop) {
                $frame = $start_frame;
                $itr = 0;
            }
        }
        glutTimerFunc(1.0 / $fps * 1000, \&timer);
        glutPostRedisplay;
    }
}

sub keyboard {
    my ($key) = @_;
    if ($key == 27) { # ESC
        destroy_shadow_map;
        glutDestroyWindow($win_id);
    } elsif ($key == ord('F') || $key == ord('f')) {
        if ($frame + 10 < $bvh->frames && (!defined($samples_m) || $itr + 1 < @$samples_m) && (!defined($samples_o) || $itr + 1 < @$samples_o)) {
        #if ($frame + 10 < $bvh->frames && $itr + 1 < @$samples) {
            $frame += 10;
            ++$itr;
            glutPostRedisplay;
        }
    } elsif ($key == ord('B') || $key == ord('b')) {
        if ($frame - 10 >= 0 && $itr - 1 >= 0) {
            $frame -= 10;
            --$itr;
            glutPostRedisplay;
        }
    } elsif ($key == ord('L') || $key == ord('l')) {
        $loop = !$loop;
    } elsif ($key == ord('[')) {
        if ($trial > 0) {
            --$trial;
            load_sample;
            glutPostRedisplay;
        }
    } elsif ($key == ord(']')) {
        ++$trial;
        load_sample;
        glutPostRedisplay;
    } elsif ($key == ord(',')) {
        if ($round > 0) {
            --$round;
            load_sample;
            glutPostRedisplay;
        }
    } elsif ($key == ord('.')) {
        ++$round;
        load_sample;
        glutPostRedisplay;
    } elsif ($key == ord('P') || $key == ord('p')) {
        $show_pose = !$show_pose;
        glutPostRedisplay;
    } elsif ($key == ord('R') || $key == ord('r')) {
        $show_ref = !$show_ref;
        glutPostRedisplay;
    } elsif ($key == ord('M') || $key == ord('m')) {
        $show_m = !$show_m;
        glutPostRedisplay;
    } elsif ($key == ord('O') || $key == ord('o')) {
        $show_o = !$show_o;
        glutPostRedisplay;
    } elsif ($key == ord('9')) {
        $alpha *= 0.9;
        glutPostRedisplay;
    } elsif ($key == ord('0')) {
        $alpha /= 0.9;
        glutPostRedisplay;
    } elsif ($key == ord('-')) {
        if ($num_of_samples - 10 > 0) {
            $num_of_samples -= 10;
            glutPostRedisplay;
        }
    } elsif ($key == ord('=')) {
        $num_of_samples += 10;
        glutPostRedisplay;
    } elsif ($key == ord('C') || $key == ord('c')) {
        $auto_center = !$auto_center;
        glutPostRedisplay;
    } elsif ($key == ord(' ')) {
        $animate = !$animate;
        if ($animate) {
            glutTimerFunc(1.0 / $fps * 1000, \&timer);
        }
    } elsif ($key == ord('V') || $key == ord('v')) {
        $recording = !$recording;
        if ($recording) {
            open $fh_ffmpeg, '|-', "$Bin/$ffmpeg -r $fps -f rawvideo -pix_fmt rgba -s ${screen_width}x${screen_height} -i - -threads 0 -preset fast -y -pix_fmt yuv420p -crf 1 -vf vflip output.mp4";
            binmode $fh_ffmpeg;
        } else {
            close $fh_ffmpeg;
        }
    } elsif ($key == ord('S') || $key == ord('s')) {
        my $png = create_write_struct;
        $png->set_IHDR({
                height     => $screen_height,
                width      => $screen_width,
                bit_depth  => 8,
                color_type => PNG_COLOR_TYPE_RGB_ALPHA,
            });
        my $buffer = OpenGL::Array->new($screen_width * $screen_height * 4, GL_BYTE);
        glReadBuffer(GL_FRONT);
        glReadPixels_c(0, 0, $screen_width, $screen_height, GL_RGBA, GL_UNSIGNED_BYTE, $buffer->ptr);
        my @rows;
        for (my $i = 0; $i < $screen_height; ++$i) {
            unshift @rows, $buffer->retrieve_data($i * $screen_width * 4, $screen_width * 4); # use unshift instead of push because we want to flip the png along y axis
        }
        $png->set_rows(\@rows);
        $png->write_png_file(sprintf('img%03d.png', $png_counter++));
    } elsif ($key == ord('A') || $key == ord('a')) {
        print "yaw: ", $camera->yaw, "\n";
        print "pitch: ", $camera->pitch, "\n";
        print "distance:", $camera->distance, "\n";
    } elsif ($key == ord('H') || $key == ord('h')) {
        print <<'HELP';

Keyboard
    ESC: exit.
    B: previous iteration (frame - 10).
    F: next iteration (frame + 10).
    L: toggle loop.
    [: previous trial.
    ]: next trial.
    ,: previous round.
    .: next round.
    P: toggle showing pose.
    R: toggle showing reference.
    M: toggle showing mass-SAMCON.
    O: toggle showing original SAMCON.
    C: toggle centering the character
    Space: animate.
    V: record video.
    S: screen shot.
    9: decrease alpha.
    0: increase alpha.
    -: decrease number of samples shown.
    +: increase number of samples shown.

Mouse
    Left button: rotate. Translate with X, Y or Z pressed.
    Right button: zoom.

HELP
    }
    $camera->keyboard_handler(@_);
}

sub keyboard_up {
    $camera->keyboard_up_handler(@_);
}

sub mouse {
    $camera->mouse_handler(@_);
}

sub motion {
    $camera->motion_handler(@_);
    #$shader->use;
    #$shader->set_mat4('view', $camera->view_matrix);
    glutPostRedisplay;
}

glutInit;
glutInitDisplayMode(GLUT_RGB | GLUT_DOUBLE);
glutInitWindowSize($screen_width, $screen_height);
$win_id = glutCreateWindow("Viewer");
glutDisplayFunc(\&render);
glutKeyboardFunc(\&keyboard);
glutKeyboardUpFunc(\&keyboard_up);
glutMouseFunc(\&mouse);
glutMotionFunc(\&motion);
glutReshapeFunc(sub {
        ($screen_width, $screen_height) = @_;
        $camera->aspect($screen_width / $screen_height);
        #$shader->use;
        #$shader->set_mat4('proj', $camera->proj_matrix);
    });

die "glewInit failed" unless glewInit() == GLEW_OK;

glEnable(GL_DEPTH_TEST);
glEnable(GL_BLEND);
glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
$shader = MotionViewer::Shader->load(File::Spec->catdir($Bin, 'simple.vs'), File::Spec->catdir($Bin, 'simple.fs'));
$shadow_map_shader = MotionViewer::Shader->load(File::Spec->catdir($Bin, 'shadow_map.vs'), File::Spec->catdir($Bin, 'shadow_map.fs'));
$primitive_shader = MotionViewer::Shader->load(File::Spec->catdir($Bin, 'primitive.vs'), File::Spec->catdir($Bin, 'primitive.fs'));
#my @vertices = (
#     0.00,  0.25, 0.00,
#    -0.25, -0.25, 0.00,
#     0.25, -0.25, 0.00,
#);
#$buffer = MotionViewer::Buffer->new(1, @vertices);
$camera = MotionViewer::Camera->new(aspect => $screen_width / $screen_height);
#$camera->yaw(-2.1);
#$camera->pitch(50);
#$camera->distance(153);
$camera->yaw(27);
$camera->pitch(7.5);
$camera->distance(200);
#$shader->use;
#$shader->set_mat4('view', $camera->view_matrix);
#$shader->set_mat4('proj', $camera->proj_matrix);

#$bvh = MotionViewer::BVH->load('walk.bvh');
#$bvh = MotionViewer::BVH->load('cmu_run_filtered.bvh');
#$bvh = MotionViewer::BVH->load('Cyrus_Take6.bvh', 'sfu_jump_geometry_config.txt');
#$bvh = MotionViewer::BVH->load('OptiTrack-IITSEC2007.bvh', 'sfu_jump_geometry_config.txt');
if ($geometry_file) {
    $bvh = MotionViewer::BVH->load($bvh_file, $geometry_file);
} else {
    $bvh = MotionViewer::BVH->load($bvh_file);
}
if (@motions) {
    $bvh->frames(scalar(@motions));
    my $i = 0;
    for (@motions) {
        $bvh->at_frame($i++, @$_);
    }
}
$shader->use;
$shader->set_vec3('lightIntensity', GLM::Vec3->new(1));
$shader->set_vec3('lightDir', GLM::Vec3->new(-1)->normalized);

load_sample;
create_floor;
create_cube;
create_sphere;
create_cylinder;
create_cone;
init_shadow_map;

glutMainLoop();
