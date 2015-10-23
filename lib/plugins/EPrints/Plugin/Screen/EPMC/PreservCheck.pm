#####################################################################
#
# EPrints::Plugin::Screen::EPMC::PreservCheck
#
######################################################################
#
#  __COPYRIGHT__
#
# Copyright 2000-2011 University of Southampton. All Rights Reserved.
# 
#  __LICENSE__
#
######################################################################
package EPrints::Plugin::Screen::EPMC::PreservCheck;

@ISA = ( 'EPrints::Plugin::Screen::EPMC' );

use strict;
# Make the plug-in
sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new( %params );

	$self->{actions} = [qw( enable disable configure )];
	$self->{disable} = 0; # always enabled, even in lib/plugins
	
	$self->{package_name} = "preservation_toolkit";

	return $self;
}

=item $screen->action_enable( [ SKIP_RELOAD ] )

Enable the L<EPrints::DataObj::EPM> for the current repository.

If SKIP_RELOAD is true will not reload the repository configuration.

=cut

sub action_enable
{
	my( $self, $skip_reload ) = @_;
	
	$self->SUPER::action_enable( $skip_reload );

	$self->droid_check();

	my $repository = $self->{repository};

	EPrints::DataObj::EventQueue->create_unique( $repository, {
		pluginid => "Event",
		action => "cron",
		params => ["0,15,30,45 * * * *",
			"Event::DroidScan",
			"scan_repository",
		],
	});

}

sub action_disable
{
	my( $self, $skip_reload ) = @_;
	
	$self->SUPER::action_disable( $skip_reload );

        my $repository = $self->{repository};
	
	my $event = EPrints::DataObj::EventQueue->new_from_hash( $repository, {
		pluginid => "Event",
		action => "cron",
		params => ["0,15,30,45 * * * *",
			"Event::DroidScan",
			"scan_repository",
		],
	});
	$event->delete if (defined $event);

        my $output_file = $repository->get_conf( "htdocs_path" ) . "/en/droid_classification_ajax.xml";

	if ( -e $output_file ) {
	        unlink($output_file);
	}
	
}

sub droid_check 
{
	
	my ( $self ) = @_;

	my $repository = $self->{repository};

	my $droid = $repository->get_conf( 'executables', 'droid' );

	if (!defined $droid) {
		$self->{processor}->add_message( "warning",$repository->xml->create_text_node("DROID not installed"));
	}

	return;
}

sub allow_configure { shift->can_be_viewed( @_ ) }

sub action_configure
{
	my( $self ) = @_;

	my $epm = $self->{processor}->{dataobj};
	my $epmid = $epm->id;

	foreach my $file ($epm->installed_files)
	{
		my $filename = $file->value( "filename" );
		next if $filename !~ m#^epm/$epmid/cfg/cfg\.d/(.*)#;
		my $url = $self->{repository}->current_url( host => 1 );
		$url->query_form(
			screen => "Admin::Config::View::Perl",
			configfile => "cfg.d/pronom.pl",
		);
		$self->{repository}->redirect( $url );
		exit( 0 );
	}

	$self->{processor}->{screenid} = "Admin::EPM";

	$self->{processor}->add_message( "error", $self->html_phrase( "missing" ) );
}

1;
