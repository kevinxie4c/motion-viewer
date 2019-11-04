#!/usr/bin/env perl
use OpenGL::Modern qw(:all);
use OpenGL::GLUT qw(:all);

use FindBin qw($Bin);
use lib $Bin;
use MotionViewer::Shader;

my $win_id;
my ($screen_width, $screen_height) = (800, 600);

sub render {
    glClearColor(1.0, 1.0, 1.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glutSwapBuffers();
}

sub keyboard {
    my $key = shift;
    if ($key == 27) { # ESC
        glutDestroyWindow($win_id);
    } 
}

glutInit;
glutInitDisplayMode(GLUT_RGB | GLUT_DOUBLE);
glutInitWindowSize($screen_width, $screen_height);
$win_id = glutCreateWindow("Viewer");
glutDisplayFunc(\&render);
glutKeyboardFunc(\&keyboard);
glutReshapeFunc(sub {
        ($screen_width, $screen_height) = @_;
        glViewport(0, 0, $screen_width, $screen_height);
    });

die "glewInit failed" unless glewInit() == GLEW_OK;

my $shader = MotionViewer::Shader->load('simple.vs', 'simple.fs');

glutMainLoop();
