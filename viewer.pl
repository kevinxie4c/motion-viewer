#!/usr/bin/env perl
use OpenGL::Modern qw(:all);
use OpenGL::GLUT qw(:all);
use OpenGL::Array;
use GLM;

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
my ($round, $trial) = (1, 1);
my ($show_pose, $show_ref) = (1, 0);
my ($show_m, $show_o) = (1, 1);
my $itr = 0;
#my $start_frame = 43;
#my $start_frame = 57;
my $start_frame = 12;
my $frame = $start_frame;
my ($samples_m, $samples_o);
my $orange = GLM::Vec3->new(1.0, 0.5, 0.2);
my $red = GLM::Vec3->new(1.0, 0.0, 0.0);
my $blue = GLM::Vec3->new(0.0, 0.0, 1.0);
my $white = GLM::Vec3->new(1.0, 1.0, 1.0);
my $alpha = 0.1;
my $num_of_samples = 20;
my $animate = 0;
my $fps = 10; # 0.1 second per iteration. 10 Hz.
my $ffmpeg = $^O eq 'MSWin32' ? 'ffmpeg.exe': 'ffmpeg';
my $fh_ffmpeg;
my $recording = 0;

my $floor_y = 0;
my $floor_half_width = 500;
my $floor_buffer;

my $shadow_map_shader;
my ($shadow_map_height, $shadow_map_width) = (4096, 4096);
my ($shadow_map_buffer, $shadow_map_texture);
my $light_space_matrix;
my ($light_near, $light_far) = (1, 1000);

my $identity_mat = GLM::Mat4->new(
    1, 0, 0, 0,
    0, 1, 0, 0,
    0, 0, 1, 0,
    0, 0, 0, 1
);


sub load_sample {
    my $trial_dir_m = File::Spec->catdir('samples_m', $round, $trial);
    my $trial_dir_o = File::Spec->catdir('samples_o', $round, $trial);
    if (-d $trial_dir_m && -d $trial_dir_o) {
        print "round=$round, trial = $trial\n";
        $samples_m = decompress $trial_dir_m;
        $samples_o = decompress $trial_dir_o;
    } else {
        warn "cannot open $trial_dir_m or $trial_dir_o\n";
    }
}

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

sub draw_floor {
    $floor_buffer->bind;
    glDrawArrays(GL_TRIANGLES, 0, 6);
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

    my $light_proj = GLM::Functions::ortho(-500, 500, -500, 500, $light_near, $light_far);
    my $light_view = GLM::Functions::lookAt(GLM::Vec3->new(200), GLM::Vec3->new(0), GLM::Vec3->new(0, 1, 0));
    $light_space_matrix = $light_proj * $light_view;
}

sub create_shadow_map {
    $shadow_map_shader->use;
    $shadow_map_shader->set_mat4('lightSpaceMatrix', $light_space_matrix);
    glViewport(0, 0, $shadow_map_width, $shadow_map_height);
    glBindFramebuffer(GL_FRAMEBUFFER, $shadow_map_buffer);
    glClear(GL_DEPTH_BUFFER_BIT);

    $shadow_map_shader->set_mat4('model', $identity_mat);
    draw_floor;
    $bvh->shader($shadow_map_shader);
    my @tmp = $bvh->at_frame($frame);
    $tmp[0] -= 50;
    $bvh->set_position(@tmp);

    $bvh->set_position($bvh->at_frame($frame));
    $bvh->draw;
    if ($show_m) {
        my $count = $num_of_samples;
        for (@{$samples_m->[$itr]}) {
            last if $count-- <= 0;
            if ($show_pose) {
                $bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                $bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
        }
    }
    if ($show_o) {
        my $count = $num_of_samples;
        for (@{$samples_o->[$itr]}) {
            last if $count-- <= 0;
            if ($show_pose) {
                my @tmp = @{$_->{pos}};
                $tmp[0] += 50;
                $bvh->set_position(@tmp);

                $bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                my @tmp = @{$_->{ref}};
                $tmp[0] += 50;
                $bvh->set_position(@tmp);

                $bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
        }
    }

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
}

sub destroy_shadow_map {
}

sub render {
    #glClearColor(0.0, 0.0, 0.0, 0.0);
    glClearColor(0.529, 0.808, 0.922, 0.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    #$shader->use;
    #$buffer->bind;
    #glDrawArrays(GL_TRIANGLES, 0, 3);
    glEnable(GL_DEPTH_TEST);

    create_shadow_map;

    glViewport(0, 0, $screen_width, $screen_height);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, $shadow_map_texture);
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
    $tmp[0] -= 50;
    $bvh->set_position(@tmp);

    $bvh->set_position($bvh->at_frame($frame));
    $bvh->draw;

    glDisable(GL_DEPTH_TEST);
    $shader->set_float('alpha', $alpha);
    if ($show_m) {
        my $count = $num_of_samples;
        for (@{$samples_m->[$itr]}) {
            last if $count-- <= 0;
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
        }
    }
    if ($show_o) {
        my $count = $num_of_samples;
        for (@{$samples_o->[$itr]}) {
            last if $count-- <= 0;
            if ($show_pose) {
                $shader->set_vec3('color', $red);

                my @tmp = @{$_->{pos}};
                $tmp[0] += 50;
                $bvh->set_position(@tmp);

                $bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                $shader->set_vec3('color', 0.7 * $red);
                
                my @tmp = @{$_->{ref}};
                $tmp[0] += 50;
                $bvh->set_position(@tmp);

                $bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
        }
    }
    glutSwapBuffers();
    if ($recording) {
        my $buffer = OpenGL::Array->new($screen_width * $screen_height * 4, GL_BYTE);
        glReadPixels_c(0, 0, $screen_width, $screen_height, GL_RGBA, GL_BYTE, $buffer->ptr);
        print $fh_ffmpeg $buffer->retrieve_data(0, $screen_width * $screen_height * 4);
    }
}

sub timer {
    if ($animate) {
        if ($frame + 10 < $bvh->frames && $itr + 1 < @$samples_m && $itr + 1 < @$samples_o) {
            $frame += 10;
            ++$itr;
        } else {
            $frame = $start_frame;
            $itr = 0;
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
        if ($frame + 10 < $bvh->frames && $itr + 1 < @$samples_m && $itr + 1 < @$samples_o) {
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
        my ($x, $y, $z) = $bvh->at_frame($frame); # Assume that the first 3 dofs are translation
        $camera->center(GLM::Vec3->new($x, $y, $z));
        $camera->update_view_matrix;
        glutPostRedisplay;
    } elsif ($key == ord(' ')) {
        $animate = !$animate;
        if ($animate) {
            glutTimerFunc(1.0 / $fps * 1000, \&timer);
        }
    } elsif ($key == ord('V') || $key == ord('v')) {
        $recording = !$recording;
        if ($recording) {
            open $fh_ffmpeg, '|-', "$ffmpeg -r $fps -f rawvideo -pix_fmt rgba -s ${screen_width}x${screen_height} -i - -threads 0 -preset fast -y -pix_fmt yuv420p -crf 1 -vf vflip output.mp4";
            binmode $fh_ffmpeg;
        } else {
            close $fh_ffmpeg;
        }
    } elsif ($key == ord('H') || $key == ord('h')) {
        print <<'HELP';

Keyboard
    ESC: exit.
    B: previous iteration (frame - 10).
    F: next iteration (frame + 10).
    [: previous trial.
    ]: next trial.
    ,: previous round.
    .: next round.
    P: toggle showing pose.
    R: toggle showing reference.
    M: toggle showing mass-SAMCON.
    O: toggle showing original SAMCON.
    C: center the character
    Space: animate.
    V: record video.
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
$shader = MotionViewer::Shader->load('simple.vs', 'simple.fs');
$shadow_map_shader = MotionViewer::Shader->load('shadow_map.vs', 'shadow_map.fs');
#my @vertices = (
#     0.00,  0.25, 0.00,
#    -0.25, -0.25, 0.00,
#     0.25, -0.25, 0.00,
#);
#$buffer = MotionViewer::Buffer->new(1, @vertices);
$camera = MotionViewer::Camera->new(aspect => $screen_width / $screen_height);
#$shader->use;
#$shader->set_mat4('view', $camera->view_matrix);
#$shader->set_mat4('proj', $camera->proj_matrix);

#$bvh = MotionViewer::BVH->load('walk.bvh');
#$bvh = MotionViewer::BVH->load('cmu_run_filtered.bvh');
$bvh = MotionViewer::BVH->load('Cyrus_Take6.bvh');
$shader->use;
$shader->set_vec3('lightIntensity', GLM::Vec3->new(1));
$shader->set_vec3('lightDir', GLM::Vec3->new(-1)->normalized);

load_sample;
create_floor;
init_shadow_map;

glutMainLoop();
