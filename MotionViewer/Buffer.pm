package MotionViewer::Buffer;

use Carp;
use OpenGL::Modern qw(:all);
use OpenGL::Array;

sub new {
    my $class = shift;
    croak 'usage: ' . $this . '->new($number_of_attributes, @data' if @_ < 2;
    my $this = bless {}, $class;
    my ($num_attr, @data) = @_;

    $this->vao_array(OpenGL::Array->new(1, GL_INT));
    glGenVertexArrays_c(1, $this->vao_array->ptr);
    glBindVertexArray($this->vao);

    $this->vbo_array(OpenGL::Array->new(1, GL_INT));
    glGenBuffers_c(1, $this->vbo_array->ptr);
    glBindBuffer(GL_ARRAY_BUFFER, $this->vbo);

    my $vertices_array = OpenGL::Array->new_list(GL_FLOAT, @data);
    glBufferData_c(GL_ARRAY_BUFFER, $vertices_array->offset(scalar(@data)) - $vertices_array->ptr, $vertices_array->ptr, GL_STATIC_DRAW);
    for (my $i = 0; $i < $num_attr; ++$i) {
        glVertexAttribPointer_c($i, 3, GL_FLOAT, GL_FALSE, $vertices_array->offset(3 * $num_attr) - $vertices_array->ptr, $vertices_array->offset(3 * $i) - $vertices_array->ptr);
        glEnableVertexAttribArray($i);
    }
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArray(0);
    $this;
}

sub vbo {
    my $this = shift;
    ($this->vbo_array->retrieve(0, 1))[0];
}

sub vao {
    my $this = shift;
    ($this->vao_array->retrieve(0, 1))[0];
}

sub vbo_array {
    my $this = shift;
    $this->{vbo_array} = shift if @_;
    $this->{vbo_array};
}

sub vao_array {
    my $this = shift;
    $this->{vao_array} = shift if @_;
    $this->{vao_array};
}

sub bind {
    my $this = shift;
    glBindVertexArray($this->vao);
}

sub unbind {
    my $this = shift;
    glBindVertexArray(0);
}

sub DESTROY {
    glDeleteVertexArrays_c(1, $this->vao_array->ptr);
    glDeleteBuffers_c(1, $this->vbo_array->ptr);
}

1;
