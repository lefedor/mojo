# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious::Controller;

use strict;
use warnings;

use base 'MojoX::Dispatcher::Routes::Controller';

use Mojo::ByteStream;
use Mojo::Exception;
use Mojo::URL;

require Carp;

# Space: It seems to go on and on forever...
# but then you get to the end and a gorilla starts throwing barrels at you.
sub client { shift->app->client }

sub finish {
    my $self = shift;

    # Resume
    $self->resume;

    # Finish WebSocket
    return $self->tx->finish if $self->tx->is_websocket;

    # Render
    $self->app->routes->auto_render($self);

    # Finish
    $self->app->finish($self);
}

sub finished {
    my $self = shift;

    # WebSocket check
    Carp::croak('No WebSocket connection in progress')
      unless $self->tx->is_websocket;

    # Callback
    my $cb = shift;

    # Connection finished
    $self->tx->finished(sub { shift and $self->$cb(@_) });
}

sub helper {
    my $self = shift;

    # Name
    return unless my $name = shift;

    # Helper
    Carp::croak(qq/Helper "$name" not found/)
      unless my $helper = $self->app->renderer->helper->{$name};

    # Run
    return wantarray ? ($self->$helper(@_)) : scalar $self->$helper(@_);
}

sub pause { shift->tx->pause }

sub receive_message {
    my $self = shift;

    # WebSocket check
    Carp::croak('No WebSocket connection to receive messages from')
      unless $self->tx->is_websocket;

    # Callback
    my $cb = shift;

    # Receive
    $self->tx->receive_message(sub { shift and $self->$cb(@_) });
}

sub redirect_to {
    my $self   = shift;
    my $target = shift;

    # Prepare location
    my $base     = $self->req->url->base->clone;
    my $location = Mojo::URL->new->base($base);

    # Path
    if ($target =~ /^\//) { $location->path($target) }

    # URL
    elsif ($target =~ /^\w+\:\/\//) { $location = $target }

    # Named
    else { $location = $self->url_for($target, @_) }

    # Code
    $self->res->code(302);

    # Location header
    $self->res->headers->location($location);

    return $self;
}

sub render {
    my $self = shift;

    # Template as single argument
    my $stash = $self->stash;
    my $template;
    $template = shift if (@_ % 2 && !ref $_[0]) || (!@_ % 2 && ref $_[1]);

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Template
    $args->{template} = $template if $template;

    # Localize layout and extends for partials
    if (!$stash->{'mojo.render'} && $args->{partial}) {
        $stash->{'mojo.render'} = 1;
        local $stash->{layout}  = undef;
        local $stash->{extends} = undef;
        return $self->render($args);
    }

    # Localize render arguments
    for my $key (keys %$args) {
        local $stash->{$key} = delete $args->{$key};
        return $self->render($args);
    }

    # Render
    delete $stash->{'mojo.render'};

    # Template
    unless ($stash->{template}) {

        # Default template
        my $controller = $stash->{controller};
        my $action     = $stash->{action};

        # Try the route name if we don't have controller and action
        unless ($controller && $action) {
            my $endpoint = $self->match->endpoint;

            # Use endpoint name as default template
            $self->stash(template => $endpoint->name)
              if $endpoint && $endpoint->name;
        }

        # Normal default template
        else {
            $self->stash(
                template => join('/', split(/-/, $controller), $action));
        }
    }

    # Render
    return $self->app->renderer->render($self);
}

sub render_data {
    my $self = shift;
    my $data = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Data
    $args->{data} = $data;

    return $self->render($args);
}

sub render_exception {
    my ($self, $e) = @_;

    # Exception
    $e = Mojo::Exception->new($e) unless ref $e;

    # Resume for exceptions
    $self->resume if $self->tx->is_paused;

    # Render exception template
    my $options = {
        template  => 'exception',
        format    => 'html',
        status    => 500,
        exception => $e
    };
    $self->app->static->serve_500($self)
      if $self->stash->{exception} || !$self->render($options);
}

sub render_inner {
    my ($self, $name, $content) = @_;

    # Initialize
    my $stash = $self->stash;
    $stash->{content} ||= {};
    $name ||= 'content';

    # Set
    $stash->{content}->{$name} ||= $content if $content;

    # Get
    $content = $stash->{content}->{$name};
    my $result = ref $content eq 'CODE' ? $content->() : $content;
    $result ||= '';
    return Mojo::ByteStream->new("$result");
}

sub render_json {
    my $self = shift;
    my $json = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # JSON
    $args->{json} = $json;

    return $self->render($args);
}

sub render_not_found {
    my $self = shift;

    # Render not found template
    my $options = {
        template  => 'not_found',
        format    => 'html',
        status    => 404,
        not_found => 1
    };
    $self->app->static->serve_404($self)
      if $self->stash->{not_found} || !$self->render($options);
}

sub render_partial {
    my $self = shift;

    # Template as single argument
    my $template;
    $template = shift if (@_ % 2 && !ref $_[0]) || (!@_ % 2 && ref $_[1]);

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Template
    $args->{template} = $template if $template;

    # Partial
    $args->{partial} = 1;

    return Mojo::ByteStream->new($self->render($args));
}

sub render_static {
    my $self = shift;
    $self->app->static->serve($self, @_);
}

sub render_text {
    my $self = shift;
    my $text = shift;

    # Arguments
    my $args = ref $_[0] ? $_[0] : {@_};

    # Data
    $args->{text} = $text;

    return $self->render($args);
}

sub resume { shift->tx->resume }

sub send_message {
    my $self = shift;

    # WebSocket check
    Carp::croak('No WebSocket connection to send message to')
      unless $self->tx->is_websocket;

    # Send
    $self->tx->send_message(@_);
}

sub url_for {
    my $self = shift;

    # Make sure we have a match for named routes
    $self->match(MojoX::Routes::Match->new->root($self->app->routes))
      unless $self->match;

    # Use match or root
    my $url = $self->match->url_for(@_);

    # Base
    $url->base($self->tx->req->url->base->clone);

    # Fix paths
    unshift @{$url->path->parts}, @{$url->base->path->parts};
    $url->base->path->parts([]);

    return $url;
}

1;
__END__

=head1 NAME

Mojolicious::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'Mojolicious::Controller';

=head1 DESCRIPTION

L<Mojolicous::Controller> is the base class for your L<Mojolicious>
controllers.
It is also the default controller class for L<Mojolicious> unless you set
C<controller_class> in your application.

=head1 ATTRIBUTES

L<Mojolicious::Controller> inherits all attributes from
L<MojoX::Dispatcher::Routes::Controller>.

=head1 METHODS

L<Mojolicious::Controller> inherits all methods from
L<MojoX::Dispatcher::Routes::Controller> and implements the following new
ones.

=head2 C<client>

    my $client = $c->client;
    
A L<Mojo::Client> prepared for the current environment.

    my $tx = $c->client->get('http://mojolicious.org');

    $c->client->post_form('http://kraih.com/login' => {user => 'mojo'});

    $c->client->get('http://mojolicious.org' => sub {
        my $client = shift;
        $c->render_data($client->res->body);
    })->process;

For async processing you can use C<pause> and C<finish>.

    $c->pause;
    $c->client->async->get('http://mojolicious.org' => sub {
        my $client = shift;
        $c->render_data($client->res->body);
        $c->finish;
    })->process;

=head2 C<finish>

    $c->finish;

Similar to C<resume> but will also trigger automatic rendering and the
C<after_dispatch> plugin hook, which would normally get disabled once a
request gets paused.
For WebSockets it will gracefully end the connection.

=head2 C<finished>

    $c->finished(sub {...});

Callback signaling that peer finished the WebSocket connection, only works if
there is currently a WebSocket connection in progress.

    $c->finished(sub {
        my $self = shift;
    });

=head2 C<helper>

    $c->helper('foo');
    $c->helper(foo => 23);

Directly call a L<Mojolicious> helper, see
L<Mojolicious::Plugin::DefaultHelpers> for a list of helpers that are always
available.

=head2 C<pause>

    $c->pause;

Pause transaction associated with this request, used for async web
applications.
Note that automatic rendering and some plugins that do state changing
operations inside the C<after_dispatch> hook won't work if you pause a
transaction.

=head2 C<receive_message>

    $c->receive_message(sub {...});

Receive messages via WebSocket, only works if there is currently a WebSocket
connection in progress.

    $c->receive_message(sub {
        my ($self, $message) = @_;
    });

=head2 C<redirect_to>

    $c = $c->redirect_to('named');
    $c = $c->redirect_to('named', foo => 'bar');
    $c = $c->redirect_to('/path');
    $c = $c->redirect_to('http://127.0.0.1/foo/bar');

Prepare a redirect response.

=head2 C<render>

    $c->render;
    $c->render(controller => 'foo', action => 'bar');
    $c->render({controller => 'foo', action => 'bar'});
    $c->render(text => 'Hello!');
    $c->render(template => 'index');
    $c->render(template => 'foo/index');
    $c->render(template => 'index', format => 'html', handler => 'epl');
    $c->render(handler => 'something');
    $c->render('foo/bar');
    $c->render('foo/bar', format => 'html');
    $c->render('foo/bar', {format => 'html'});

This is a wrapper around L<MojoX::Renderer> exposing pretty much all
functionality provided by it.
It will set a default template to use based on the controller and action name
or fall back to the route name.
You can call it with a hash of options which can be preceded by an optional
template name.
Note that all render arguments get localized, so stash values won't be
changed after the render call.

=head2 C<render_data>

    $c->render_data($bits);

Render binary data, similar to C<render_text> but data will not be encoded.

=head2 C<render_exception>

    $c->render_exception($e);

Render the exception template C<exception.html.$handler>.
Will set the status code to C<500> meaning C<Internal Server Error>.
Takes a L<Mojo::Exception> object or error message and will fall back to
rendering a static C<500> page using L<MojoX::Renderer::Static>.

=head2 C<render_inner>

    my $output = $c->render_inner;
    my $output = $c->render_inner('content');
    my $output = $c->render_inner(content => 'Hello world!');
    my $output = $c->render_inner(content => sub { 'Hello world!' });

Contains partial rendered templates, used for the renderers C<layout> and
C<extends> features.

=head2 C<render_json>

    $c->render_json({foo => 'bar'});
    $c->render_json([1, 2, -3]);

Render a data structure as JSON.

=head2 C<render_not_found>

    $c->render_not_found;
    
Render the not found template C<not_found.html.$handler>.
Also sets the response status code to C<404>, will fall back to rendering a
static C<404> page using L<MojoX::Renderer::Static>.

=head2 C<render_partial>

    my $output = $c->render_partial;
    my $output = $c->render_partial(action => 'foo');
    
Same as C<render> but returns the rendered result.

=head2 C<render_static>

    $c->render_static('images/logo.png');

Render a static asset using L<MojoX::Dispatcher::Static>.

=head2 C<render_text>

    $c->render_text('Hello World!');
    $c->render_text('Hello World', layout => 'green');

Render the givent content as plain text, note that text will be encoded.
See C<render_data> for an alternative without encoding.

=head2 C<resume>

    $c->resume;

Resume transaction associated with this request, used for async web
applications.

=head2 C<send_message>

    $c->send_message('Hi there!');

Send a message via WebSocket, only works if there is currently a WebSocket
connection in progress.

=head2 C<url_for>

    my $url = $c->url_for;
    my $url = $c->url_for(controller => 'bar', action => 'baz');
    my $url = $c->url_for('named', controller => 'bar', action => 'baz');

Generate a L<Mojo::URL> for the current or a named route.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<http://mojolicious.org>.

=cut
