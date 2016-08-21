package Dancer2::Plugin::Tail;

use warnings;
use strict;
use Carp;
use Session::Token;

use Dancer2::Core::Types qw(Bool HashRef Str);
use Dancer2::Plugin;


=head1 NAME

Dancer2::Plugin::Tail - Tail a file from Dancer2

=head1 VERSION

Version 0.006

=cut

our $VERSION = '0.006';


=head1 SYNOPSIS

  use Dancer2;
  use Dancer2::Plugin::Tail;

=head1 DESCRIPTION

This plugin will allow you to tail a file from within Dancer2.  It's designed to be unobtrusive.  So, it is functional just by calling it from your scripts.  Edit entries in the configuration file to setup routes and activate files that may be tailed.  Additionally, you may define or restrict definition of tailed files.

=head1 CONFIGURATION

You may specify the route and access to files.  The plugin will only read files so it must have read access to them.  The above configuration will generate two routes: '/tail/display' and '/tail/read'.  

The display section defines the 

A sample HTML page with Bootstrap and jQuery is included in the samples directory.  Use it as an example  to build your own page.

  plugins:
    Tail:
      update_interval: 3000
      tmpdir:          '/tmp'
      no_user_defined: 1
      no_defaults:     0
      display:
        method:    'get'
        url:       '/tail/display'
        template:  'tail.tt'
        layout:    'nomenu.tt'
      data:
        method:    'get'
        url:       '/tail/read'
      files:
        id1:    
          heading: 'Server Access Log'
          file:    '/var/logs/access_log'
        id2:    
          heading: 'Server Error Log'
          file:    '/var/logs/error_log'

=over 

=item I<update_interval>

Specify an update interval.  Default is 3000.  This value is passed to your web page or window.  See example that's included.


=item I<tmpdir>

location of user generted files to tail.  Default is '/tmp'.


=item I<no_user_defined>

Specifies if user can call tail dynamically on any file.  This is useful for tailing user generated log files.

B<Note> that you B<must> have a session provider configured to dynamically tail files using this plugin.  This plugin requires sessions in order to track information about user defined tailed files for the logged in user.
Please see L<Dancer2::Core::Session> for information on how to configure session management within your application.


=item I<no_defaults>

Specifies if defaults should be ignored.


=item I<display>

Defines display settings.

=over 4

=item I<method>

Default 'get'.


=item I<url>

Route in Dancer to display template for tailing.  Default '/tail/display'


=item I<template>

Template of tail screen. Default 'tail.tt'

=item I<layout>

Layout of template.  This is useful when opening a window to tail files.

=back

=item I<data>

Defines file tail settings.

=over 4

=item I<method>

Default 'get'.


=item I<url>

Route in Dancer to tail files.  Default '/tail/read'

=back

=item I<files>

List of predefine files that can be tailed.

=over 

=item I<ID>

Define a unique ID for this file

=over 

=item I<heading>

This is a heading to be passed to the template.  Use it as a short description to the file you're taiing.

=item I<file>

Full path and file name to tail.


=back 

=cut 

#
# Accessors
#
has update_interval => (
  is          => 'ro',
  isa         => Str,
  from_config => 1,
  default     => sub { '3000' },    # 3 second interval
);

has no_user_defined => (
  is          => 'ro',
  isa         => Bool,
  from_config => sub { 1 },
);

has no_defaults => (
  is          => 'ro',
  isa         => Bool,
  from_config => sub { 0 },
);

has data_method => (
  is          => 'ro',
  isa         => Str,
  from_config => 'data.method',
  default     => sub { 'get' }
);

has data_url => (
  is          => 'ro',
  isa         => Str,
  from_config => 'data.url',
  default     => sub { '/tail/read' }
);

has display_method => (
  is          => 'ro',
  isa         => Str,
  from_config => 'display.method',
  default     => sub { 'get' }
);

has display_url => (
  is          => 'ro',
  isa         => Str,
  from_config => 'display.url',
  default     => sub { '/tail/display' },
);

has display_template => (
  is          => 'ro',
  isa         => Str,
  from_config => 'display.template',
  default     => sub { 'tail.tt' },
);

has display_layout => (
  is          => 'ro',
  isa         => Str,
  from_config => 'display.layout',
  default     => sub { '' },
);

has tmpdir => (
  is          => 'ro',
  isa         => Str,
  from_config => 1,
  default     => sub { '/tmp' },    # write to /tmp
);

has files => (
  is          => 'ro',
  isa         => HashRef,
  from_config => 1,
  default     => sub { {} },    # Empty
);

sub _new_file_id {
  Session::Token->new( length => 32 )->get;
}

# Generate routes based on configuration settings
sub BUILD {
  my $plugin = shift;
  my $app    = $plugin->app;

  if ( ! $plugin->no_defaults ) {

    # Setup route to display a template for the tail
    my $disp_method   = $plugin->display_method;
    my $disp_url      = $plugin->display_url;
  
    $plugin->app->add_route(
      method => $disp_method,
      regexp => qr!$disp_url!,
      code   => \&display_tail,
    );
  
    # Setup a route to return json data of the file
    my $data_url    = $plugin->data_url;
    my $data_method = $plugin->data_method;
  
    # Use regexp to match part of the file, then splat inside code
    $plugin->app->add_route(
      method => $data_method,
      regexp => qr!^$data_url!,
      code   => \&tail_file,
    );
  }

}    ### BUILD


# Function to display template
sub display_tail {
  my $app    = shift;
  my $plugin = $app->with_plugin('Tail');

  my $file_id  = $app->request->params->{id};
  my $curr_pos = $app->request->params->{curr_pos};

  my $files = $plugin->files;

  croak "The specified id: $file_id is not properly defined in your configuration."
    if ( ! $files->{$file_id}->{file} );

  $app->template($plugin->display_template, 
                  { id       => $file_id,
                    curr_pos => $curr_pos,
                    title    => $files->{$file_id}->{heading} },
                  { layout => $plugin->display_layout }) ;
}              

# Function for a user to dynamically define a file 
sub define_file_to_tail {
  my ( $plugin, %params ) = @_;
  
  if ( ! defined $params{file} || ! -e $params{file} ) {
    return "No filname passed or file does not exist.";
  }

  my $file_id = _new_file_id();         # Create a new file id
  my $session = $plugin->app->session;  # Get the session
  $session->write( $file_id, %params);   # Store the file name into 

  return $file_id;
}

# Function to tail a file
sub tail_file {
  my $app    = shift;
  my $plugin = $app->with_plugin('Tail');

  my $file_id  = $app->request->params->{id};
  my $curr_pos = $app->request->params->{curr_pos};

  my $files    = $plugin->files;

  # setup keyword if available
  if ( $plugin->no_user_defined ) {
    my $session = $plugin->app->session;  
    $files->{$file_id} = $session->read( $file_id ) if $session->read($file_id);   
  }

  my $log_file = $files->{$file_id}->{file} || '';

  if ( $log_file ne '' && -e $log_file ) {

    my ($output, $whence);

    open(my $IN, '<', $log_file);  # Open file for reading

    # Add header if it's 1st request
    if ( $curr_pos < 1 ) {
      $output = "$log_file\n";
    }

    # Determine where to start reading
    if ( $curr_pos < 0 ) {
      $whence = 2; # Relative to current position
    } else {
      $whence = 1; # Absolute current position
    }

    seek( $IN, $curr_pos, $whence ); # Seek the place 
                                                          # where we were last
    while ( my $line = <$IN> ) {     # Continue until end
      $output .= $line ;
    }

    my $file_end = tell($IN);   # Figure out the end 
                                                     #  of the file
    close($IN);
    # Return JSON
    $app->send_as( JSON => { new_curr_pos => $file_end, 
                             interval     => $plugin->update_interval,
                             output       => $output } );

  } else {  ### if -e

  }
}    

# setup keywords
plugin_keywords qw( tail_file define_file_to_tail );

=back

=back

=head1 AUTHOR

Hagop "Jack" Bilemjian, C<< <jck000 at gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-dancer2-plugin-tail at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Dancer2-Plugin-Tail>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Dancer2::Plugin::Tail


You can also look for information at:

=over 

=item * RT: CPAN's request tracker (report bugs here)

L<https://github.com/jck000/Dancer2-Plugin-Tail/issues>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Dancer2-Plugin-Tail>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Dancer2-Plugin-Tail>

=item * Search CPAN

L<http://search.cpan.org/dist/Dancer2-Plugin-Tail/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2015-2016 Hagop "Jack" Bilemjian.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=head1 SEE ALSO
 
L<Dancer2>
 
L<Dancer2::Plugin>
 
=cut

1; # End of Dancer2::Plugin::Tail
