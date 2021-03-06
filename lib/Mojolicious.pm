# Copyright (C) 2008-2010, Sebastian Riedel.

package Mojolicious;

use strict;
use warnings;

use base 'Mojo';

use Mojolicious::Commands;
use Mojolicious::Plugins;
use MojoX::Dispatcher::Routes;
use MojoX::Dispatcher::Static;
use MojoX::Renderer;
use MojoX::Session::Cookie;
use MojoX::Types;

__PACKAGE__->attr(controller_class => 'Mojolicious::Controller');
__PACKAGE__->attr(mode => sub { ($ENV{MOJO_MODE} || 'development') });
__PACKAGE__->attr(plugins  => sub { Mojolicious::Plugins->new });
__PACKAGE__->attr(renderer => sub { MojoX::Renderer->new });
__PACKAGE__->attr(routes   => sub { MojoX::Dispatcher::Routes->new });
__PACKAGE__->attr(
    secret => sub {
        my $self = shift;

        # Warn developers about unsecure default
        $self->log->debug('Your secret passphrase needs to be changed!!!');

        # Application name
        return ref $self;
    }
);
__PACKAGE__->attr(session => sub { MojoX::Session::Cookie->new });
__PACKAGE__->attr(static  => sub { MojoX::Dispatcher::Static->new });
__PACKAGE__->attr(types   => sub { MojoX::Types->new });

our $CODENAME = 'Snowman';
our $VERSION  = '0.999925';

sub new {
    my $self = shift->SUPER::new(@_);

    # Transaction builder
    $self->build_tx_cb(
        sub {
            my $self = shift;

            # Build
            my $tx = Mojo::Transaction::HTTP->new;

            # Hook
            $self->plugins->run_hook_reverse(after_build_tx => $tx);

            return $tx;
        }
    );

    # Namespace
    $self->routes->namespace(ref $self);

    # Types
    $self->renderer->types($self->types);
    $self->static->types($self->types);

    # Root
    $self->renderer->root($self->home->rel_dir('templates'));
    $self->static->root($self->home->rel_dir('public'));

    # Hide own controller methods
    $self->routes->hide(qw/client cookie finish finished flash helper/);
    $self->routes->hide(qw/param pause receive_message redirect_to render/);
    $self->routes->hide(qw/render_data render_exception render_inner/);
    $self->routes->hide(qw/render_json render_not_found render_partial/);
    $self->routes->hide(qw/render_static render_text resume send_message/);
    $self->routes->hide(qw/session signed_cookie url_for/);

    # Mode
    my $mode = $self->mode;

    # Log file
    $self->log->path($self->home->rel_file("log/$mode.log"))
      if -w $self->home->rel_file('log');

    # Plugins
    $self->plugin('agent_condition');
    $self->plugin('default_helpers');
    $self->plugin('epl_renderer');
    $self->plugin('ep_renderer');
    $self->plugin('request_timer');
    $self->plugin('powered_by');

    # Reduced log output outside of development mode
    $self->log->level('error') unless $mode eq 'development';

    # Run mode
    $mode = $mode . '_mode';
    $self->$mode(@_) if $self->can($mode);

    # Startup
    $self->startup(@_);

    return $self;
}

# The default dispatchers with exception handling
sub dispatch {
    my ($self, $c) = @_;

    # Session
    $self->session->load($c);

    # Hook
    $self->plugins->run_hook(before_dispatch => $c);

    # New request
    my $path = $c->req->url->path           || '/';
    my $ua   = $c->req->headers->user_agent || 'Anonymojo';
    $self->log->debug(qq/*** Request for "$path" from "$ua". ***/);

    # Try to find a static file
    my $e = $self->static->dispatch($c);

    # Hook
    $self->plugins->run_hook_reverse(after_static_dispatch => $c);

    # Use routes if we don't have a response yet
    $e = $self->routes->dispatch($c) if $e;

    # Exception
    if (ref $e) { $c->render_exception($e) }

    # Nothing found
    elsif ($e) { $c->render_not_found }

    # Finish
    $self->finish($c);
}

sub finish {
    my ($self, $c) = @_;

    # Already finished
    return if $c->stash->{finished};

    # Paused
    return if $c->tx->is_paused;

    # Hook
    $self->plugins->run_hook_reverse(after_dispatch => $c);

    # Session
    $self->session->store($c);

    # Finished
    $c->stash->{finished} = 1;
}

# Bite my shiny metal ass!
sub handler {
    my ($self, $tx) = @_;

    # Load controller class
    my $class = $self->controller_class;
    if (my $e = Mojo::Loader->load($class)) {
        $self->log->error(
            ref $e
            ? qq/Can't load controller class "$class": $e/
            : qq/Controller class "$class" doesn't exist./
        );
    }

    # Embedded application
    my $stash = {};
    if ($tx->can('stash')) {
        $stash = $tx->stash;
        $tx    = $tx->tx;
    }

    # Build default controller and process
    eval {
        $self->process($class->new(app => $self, stash => $stash, tx => $tx));
    };
    $self->log->error("Processing request failed: $@") if $@;
}

sub plugin {
    my $self = shift;
    $self->plugins->load_plugin($self, @_);
}

# This will run for each request
sub process { shift->dispatch(@_) }

# Start command system
sub start {
    my $class = shift;

    # We can be called on class or instance
    $class = ref $class || $class;

    # We are the application
    $ENV{MOJO_APP} ||= $class;

    # Start!
    return Mojolicious::Commands->start(@_);
}

# This will run once at startup
sub startup { }

1;
__END__

=head1 NAME

Mojolicious - The Web In A Box!

=head1 SYNOPSIS

    # Mojolicious application
    package MyApp;

    use base 'Mojolicious';

    sub startup {
        my $self = shift;

        # Routes
        my $r = $self->routes;

        # Default route
        $r->route('/:controller/:action/:id')->to('foo#welcome');
    }

    # Mojolicious controller
    package MyApp::Foo;

    use base 'Mojolicious::Controller';

    # Say hello
    sub welcome {
        my $self = shift;
        $self->render_text('Hi there!');
    }

    # Say goodbye from a template (foo/bye.html.ep)
    sub bye { shift->render }

=head1 DESCRIPTION

Back in the early days of the web there was this wonderful Perl library
called L<CGI>, many people only learned Perl because of it.
It was simple enough to get started without knowing much about the language
and powerful enough to keep you going, learning by doing was much fun.
While most of the techniques used are outdated now, the idea behind it is
not.
L<Mojolicious> is a new attempt at implementing this idea using state of the
art technology.

=head2 Features

=over 4

An amazing MVC web framework supporting a simplified single file mode through
L<Mojolicious::Lite>.

Very clean, portable and Object Oriented pure Perl API without any hidden
magic and no requirements besides Perl 5.8.1.

Full stack HTTP 1.1 and WebSocket client/server implementation with IPv6,
TLS, IDNA, pipelining, chunking and multipart support.

Builtin async IO and prefork web server supporting epoll, kqueue, hot
deployment and UNIX domain socket sharing, perfect for embedding.

CGI, FastCGI and L<PSGI> support.

Fresh code, based upon years of experience developing Catalyst.

Powerful out of the box with RESTful routes, plugins, sessions, signed
cookies, static file server, testing framework, Perl-ish templates, JSON,
I18N, first class Unicode support and much more for you to discover!

=back

=head2 Duct Tape For The HTML5 Web

Web development for humans, making hard things possible and everything fun.

    use Mojolicious::Lite;

    get '/hello' => sub { shift->render_text('Hello World!') }

    get '/time' => 'clock';

    websocket '/echo' => sub {
        my $self = shift;
        $self->receive_message(
            sub {
                my ($self, $message) = @_;
                $self->send_message("echo: $message");
            }
        );
    };

    get '/fetch' => sub {
        my $self = shift;
        $self->render_data(
            $self->client->get('http://mojolicious.org')->res->body);
    };

    post '/:name' => sub {
        my $self = shift;
        my $name = $self->param('name') || 'Mojo';
        $self->render_text("Hello $name!");
    };

    app->start;
    __DATA__

    @@ clock.html.ep
    % my ($second, $minute, $hour) = (localtime(time))[0, 1, 2];
    The time is <%= $hour %>:<%= $minute %>:<%= $second %>.

For more user friendly documentation see L<Mojolicious::Guides> and
L<Mojolicious::Lite>.

=head2 The Cake

    .---------------------------------------------------------------.
    |                             Fun!                              |
    '---------------------------------------------------------------'
    .---------------------------------------------------------------.
    |                                                               |
    |                .----------------------------------------------'
    |                | .--------------------------------------------.
    |   Application  | |              Mojolicious::Lite             |
    |                | '--------------------------------------------'
    |                | .--------------------------------------------.
    |                | |                 Mojolicious                |
    '----------------' '--------------------------------------------'
    .---------------------------------------------------------------.
    |                             Mojo                              |
    '---------------------------------------------------------------'
    .-------. .-----------. .--------. .------------. .-------------.
    |  CGI  | |  FastCGI  | |  PSGI  | |  HTTP 1.1  | |  WebSocket  |
    '-------' '-----------' '--------' '------------' '-------------'

=head1 ATTRIBUTES

L<Mojolicious> inherits all attributes from L<Mojo> and implements the
following new ones.

=head2 C<mode>

    my $mode = $mojo->mode;
    $mojo    = $mojo->mode('production');

The operating mode for your application.
It defaults to the value of the environment variable C<MOJO_MODE> or
C<development>.
Mojo will name the log file after the current mode and modes other than
C<development> will result in limited log output.

If you want to add per mode logic to your application, you can add a sub
to your application named C<$mode_mode>.

    sub development_mode {
        my $self = shift;
    }

    sub production_mode {
        my $self = shift;
    }

=head2 C<plugins>

    my $plugins = $mojo->plugins;
    $mojo       = $mojo->plugins(Mojolicious::Plugins->new);

The plugin loader, by default a L<Mojolicious::Plugins> object.
You can usually leave this alone, see L<Mojolicious::Plugin> if you want to
write a plugin.

=head2 C<renderer>

    my $renderer = $mojo->renderer;
    $mojo        = $mojo->renderer(MojoX::Renderer->new);

Used in your application to render content, by default a L<MojoX::Renderer>
object.
The two main renderer plugins L<Mojolicious::Plugin::EpRenderer> and
L<Mojolicious::Plugin::EplRenderer> contain more specific information.

=head2 C<routes>

    my $routes = $mojo->routes;
    $mojo      = $mojo->routes(MojoX::Dispatcher::Routes->new);

The routes dispatcher, by default a L<MojoX::Dispatcher::Routes> object.
You use this in your startup method to define the url endpoints for your
application.

    sub startup {
        my $self = shift;

        my $r = $self->routes;
        $r->route('/:controller/:action')->to('test#welcome');
    }

=head2 C<secret>

    my $secret = $mojo->secret;
    $mojo      = $mojo->secret('passw0rd');

A secret passphrase used for signed cookies and the like, defaults to the
application name which is not very secure, so you should change it!!!
As long as you are using the unsecure default there will be debug messages in
the log file reminding you to change your passphrase.

=head2 C<static>

    my $static = $mojo->static;
    $mojo      = $mojo->static(MojoX::Dispatcher::Static->new);

For serving static assets from your C<public> directory, by default a
L<MojoX::Dispatcher::Static> object.

=head2 C<types>

    my $types = $mojo->types;
    $mojo     = $mojo->types(MojoX::Types->new);

Responsible for tracking the types of content you want to serve in your
application, by default a L<MojoX::Types> object.
You can easily register new types.

    $mojo->types->type(vti => 'help/vampire');

=head1 METHODS

L<Mojolicious> inherits all methods from L<Mojo> and implements the following
new ones.

=head2 C<new>

    my $mojo = Mojolicious->new;

Construct a new L<Mojolicious> application.
Will automatically detect your home directory and set up logging based on
your current operating mode.
Also sets up the renderer, static dispatcher and a default set of plugins.

=head2 C<dispatch>

    $mojo->dispatch($c);

The heart of every Mojolicious application, calls the static and routes
dispatchers for every request.

=head2 C<finish>

    $mojo->finish($c);

Clean up after processing a request, usually called automatically.

=head2 C<handler>

    $tx = $mojo->handler($tx);

Sets up the default controller and calls process for every request.

=head2 C<plugin>

    $mojo->plugin('something');
    $mojo->plugin('something', foo => 23);
    $mojo->plugin('something', {foo => 23});

Load a plugin.

=head2 C<process>

    $mojo->process($c);

This method can be overloaded to do logic on a per request basis, by default
just calls dispatch.
Generally you will use a plugin or controller instead of this, consider it
the sledgehammer in your toolbox.

    sub process {
        my ($self, $c) = @_;
        $self->dispatch($c);
    }

=head2 C<start>

    Mojolicious->start;
    Mojolicious->start('daemon');

Start the L<Mojolicious::Commands> command line interface for your
application.

=head2 C<startup>

    $mojo->startup;

This is your main hook into the application, it will be called at application
startup.

    sub startup {
        my $self = shift;
    }

=head1 SUPPORT

=head2 Web

    http://mojolicious.org

=head2 IRC

    #mojo on irc.perl.org

=head2 Mailing-List

    http://groups.google.com/group/mojolicious

=head1 DEVELOPMENT

=head2 Repository

    http://github.com/kraih/mojo

=head1 AUTHOR

Sebastian Riedel, C<sri@cpan.org>.

=head1 CREDITS

In alphabetical order:

Adam Kennedy

Adriano Ferreira

Alex Salimon

Alexey Likhatskiy

Anatoly Sharifulin

Andre Vieth

Andrew Fresh

Andreas Koenig

Andy Grundman

Aristotle Pagaltzis

Ask Bjoern Hansen

Audrey Tang

Breno G. de Oliveira

Burak Gursoy

Ch Lamprecht

Christian Hansen

David Davis

Dmitry Konstantinov

Gisle Aas

Glen Hinkle

Graham Barr

James Duncan

Jaroslav Muhin

Jesse Vincent

Kazuhiro Shibuya

Kevin Old

Lars Balker Rasmussen

Leon Brocard

Maik Fischer

Marcus Ramberg

Mark Stosberg

Matthew Lineen

Maksym Komar

Maxim Vuets

Mirko Westermeier

Pascal Gaudette

Pedro Melo

Pierre-Yves Ritschard

Rafal Pocztarski

Randal Schwartz

Robert Hicks

Ryan Jendoubi

Sascha Kiefer

Sergey Zasenko

Shu Cho

Stanis Trendelenburg

Tatsuhiko Miyagawa

Uwe Voelker

Viacheslav Tykhanovskyi

Yaroslav Korshak

Yuki Kimoto

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008-2010, Sebastian Riedel.

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

=cut
