#!/usr/bin/env perl
use OpenGL::Modern qw(:all);
use OpenGL::GLUT qw(:all);

use FindBin qw($Bin);
use lib $Bin;
use MotionViewer::Shader;
use MotionViewer::Buffer;
use MotionViewer::Camera;
use MotionViewer::BVH;

my $win_id;
my ($screen_width, $screen_height) = (800, 600);
my ($shader, $buffer, $camera);
my $bvh;

sub render {
    glClearColor(0.0, 0.0, 0.0, 0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    #$shader->use;
    #$buffer->bind;
    #glDrawArrays(GL_TRIANGLES, 0, 3);
    $bvh->draw;
    glutSwapBuffers();
}

sub keyboard {
    my $key = shift;
    if ($key == 27) { # ESC
        glutDestroyWindow($win_id);
    } elsif ($key == ord('F') || $key == ord('f')) {
        my $frame = $bvh->frame + 1;
        $frame %= $bvh->frames if $frame >= $bvh->frames;
        $bvh->frame($frame);
        glutPostRedisplay;
    } elsif ($key == ord('B') || $key == ord('b')) {
        my $frame = $bvh->frame - 1;
        $frame += $bvh->frames if $frame < 0;
        $bvh->frame($frame);
        glutPostRedisplay;
    }
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

$bvh = MotionViewer::BVH->load('sample.bvh');
$bvh->camera($camera);
$bvh->shader($shader);

glutMainLoop();
