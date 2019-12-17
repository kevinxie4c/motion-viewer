#!/usr/bin/env perl
use OpenGL::Modern qw(:all);
use OpenGL::GLUT qw(:all);

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
my ($screen_width, $screen_height) = (800, 600);
my ($shader, $buffer, $camera);
my $bvh;
my ($round, $trial) = (1, 1);
my ($show_pose, $show_ref) = (1, 0);
my ($show_m, $show_o) = (1, 1);
my $itr = 0;
my $frame = 43;
my ($samples_m, $samples_o);
my $orange = GLM::Vec3->new(1.0, 0.5, 0.2);
my $red = GLM::Vec3->new(1.0, 0.0, 0.0);
my $blue = GLM::Vec3->new(0.0, 0.0, 1.0);
my $alpha = 0.02;

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

sub render {
    #glClearColor(0.0, 0.0, 0.0, 0.0);
    glClearColor(0.529, 0.808, 0.922, 0.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    #$shader->use;
    #$buffer->bind;
    #glDrawArrays(GL_TRIANGLES, 0, 3);
    $bvh->shader->use;
    $bvh->shader->set_mat4('view', $camera->view_matrix);
    $bvh->shader->set_mat4('proj', $camera->proj_matrix);
    $bvh->shader->set_vec3('color', $orange);
    $bvh->shader->set_float('alpha', 1.0);
    $bvh->set_position($bvh->at_frame($frame));
    $bvh->draw;
    $bvh->shader->set_float('alpha', $alpha);
    if ($show_m) {
        for (@{$samples_m->[$itr]}) {
            if ($show_pose) {
                $bvh->shader->set_vec3('color', $blue);
                $bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                $bvh->shader->set_vec3('color', 0.7 * $blue);
                $bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
        }
    }
    if ($show_o) {
        for (@{$samples_o->[$itr]}) {
            if ($show_pose) {
                $bvh->shader->set_vec3('color', $red);
                $bvh->set_position(@{$_->{pos}});
                $bvh->draw;
            }
            if ($show_ref) {
                $bvh->shader->set_vec3('color', 0.7 * $red);
                $bvh->set_position(@{$_->{ref}});
                $bvh->draw;
            }
        }
    }
    glutSwapBuffers();
}

sub keyboard {
    my ($key) = @_;
    if ($key == 27) { # ESC
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
    } elsif ($key == ord('C') || $key == ord('c')) {
        my ($x, $y, $z) = $bvh->at_frame($frame); # Assume that the first 3 dofs are translation
        $camera->center(GLM::Vec3->new($x, $y, $z));
        $camera->update_view_matrix;
        glutPostRedisplay;
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
    9: decrease alpha
    0: increase alpha

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
        glViewport(0, 0, $screen_width, $screen_height);
        $camera->aspect($screen_width / $screen_height);
        #$shader->use;
        #$shader->set_mat4('proj', $camera->proj_matrix);
    });

die "glewInit failed" unless glewInit() == GLEW_OK;

glDisable(GL_DEPTH_TEST);
#glEnable(GL_DEPTH_TEST);
glEnable(GL_BLEND);
glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
$shader = MotionViewer::Shader->load('simple.vs', 'simple.fs');
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

$bvh = MotionViewer::BVH->load('walk.bvh');
$bvh->shader($shader);
$bvh->shader->use;
$bvh->shader->set_vec3('lightIntensity', GLM::Vec3->new(1));
$bvh->shader->set_vec3('lightDir', GLM::Vec3->new(-1)->normalized);

load_sample;

glutMainLoop();
