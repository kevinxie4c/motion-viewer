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
my ($round, $trial) = (1, 1);
my $itr = 0;
my @samples;

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
    for (values %{$samples[$itr]}) {
        $bvh->at_frame($bvh->frame, @{$_->{pos}});
        $bvh->draw;
    }
    glutSwapBuffers();
}

sub keyboard {
    my $key = shift;
    if ($key == 27) { # ESC
        glutDestroyWindow($win_id);
    } elsif ($key == ord('F') || $key == ord('f')) {
        #my $frame = $bvh->frame + 1;
        #$frame %= $bvh->frames if $frame >= $bvh->frames;
        #$bvh->frame($frame);
        ++$itr;
        $itr %= @samples if $itr >= @samples;
        glutPostRedisplay;
    } elsif ($key == ord('B') || $key == ord('b')) {
        #my $frame = $bvh->frame - 1;
        #$frame += $bvh->frames if $frame < 0;
        #$bvh->frame($frame);
        --$itr;
        $itr += @samples if $itr < 0;
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

glEnable(GL_DEPTH_TEST);
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

for my $dir(glob "samples/$round/$trial/*") {
    die "$dir does not look like a number" unless $dir =~ /(\d+)$/;
    my $i = $1;
    for my $name(glob "$dir/*.txt") {
        open my $fh, '<', $name;
        $_ = <$fh>;
        $samples[$i]{$name}{pos} = [split];
    }
}

glutMainLoop();
