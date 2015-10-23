package EPrints::Plugin::Screen::Admin::FormatsRisks_download;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new {
	my( $class, %params ) = @_;
 	
	my $self = $class->SUPER::new(%params);

	$self->{actions} = [qw/ get_files /];

	return $self;
}

sub action_get_files {
	my ( $self ) = @_;

	my $format = $self->{session}->param( "format" );
	my $count = $self->{session}->param( "count" );

#print STDERR "REQUESTED " . $format . " : " . $count . "\n\n";

	if ($format eq "") {
		$self->{processor}->add_message(
				"error",
				$self->html_phrase( "no_format" )
				);

		$self->{processor}->{screenid} = "Admin::FormatsRisks";
		return 0;
	}


	my $session = $self->{session};
	my $dataset = $session->get_repository->get_dataset( "file" );	

	my $searchexp = EPrints::Search->new( 
			session => $session, 
			dataset => $dataset,
			custom_order => "filesize", 
			filters => [ 
			{ meta_fields => [qw( datasetid )], value => "document" }, 
			{ meta_fields => [qw( pronomid )], value => "$format", match => "EX" }, 
			], 
			); 

	my $list = $searchexp->perform_search; 
	if ($count > $list->count) {
		$count = $list->count;
	}
	my @files = ();
	if ($count > 1) {
		@files = push_top_to_array($session,\@files,$list);
		reverse($list);
		@files = push_top_to_array($session,\@files,$list);
	}
	my $done = @files;
	if (($count - $done) > 1) {
		my $searchexp = EPrints::Search->new( 
			session => $session, 
			dataset => $dataset,
			custom_order => "mtime", 
			filters => [ 
			{ meta_fields => [qw( datasetid )], value => "document" }, 
			{ meta_fields => [qw( pronomid )], value => "$format", match => "EX" }, 
			], 
			); 

		my $list = $searchexp->perform_search; 
		@files = push_top_to_array($session,\@files,$list);
		reverse($list);
		@files = push_top_to_array($session,\@files,$list);
	}
	
	my @ids = List::Util::shuffle(@{$list->get_ids});
	$list = EPrints::List->new(
		session => $session,
		dataset => $dataset,
		ids => \@ids );
	
	$done = @files;
	while ($done < $count) {
		my $runner = 1;
		$list->map( sub {  
			my $file = $_[2];        
			$runner++;
			});

		@files = push_top_to_array($session,\@files,$list);
		$done = @files;
	}

	my $zip_executable = $self->{session}->get_repository->get_conf('executables','zip');
	my $tmpfile = File::Temp->new( SUFFIX => ".zip" );
	unlink($tmpfile);
	my $cmd = "zip -j $tmpfile";
	foreach my $file (@files) {
		my $file_path = $file->get_local_copy();
		$cmd = $cmd . " " . $file_path;
	}
	system($cmd);
	my $result = 1;
	if ( !-s "$tmpfile" )
	{
		$result = 0;
	}
	if ($result ==1) 
	{
		seek($tmpfile, 0, 0);
		$self->{processor}->{tarball} = $tmpfile;
	} else {
		$self->{processor}->add_message(
				"error",
				$self->html_phrase( "failed" )
				);
		$self->{processor}->{screenid} = "Admin::FormatsRisks";
	}

}

sub push_top_to_array
{
	my( $session, $files, $list) = @_;

	my $running = 1;
	$list->map( sub {  
		my $file = $_[2];
		if ($running == 1) {
			if (!in_array($files,$file)) {
				push(@{$files},$file);
				$running++;
			}
		}
	} );

	return @{$files};
	
}

sub in_array
{
     my ($arr,$search_for) = @_;
     my $hash = $search_for->get_value('hash'); 
     my $filename = $search_for->get_value('filename'); 
     foreach my $file (@{$arr}) {
	if ($file->get_value('hash') eq $hash) {
		return 1;
	} elsif ($file->get_value('filename') eq $filename) {
		return 1;
	}
     }
     return 0;
     
}

sub allow_get_files
{
	my( $self ) = @_;
	return 1;
}

sub wishes_to_export
{
	my( $self ) = @_;

	if( !defined( $self->{processor}->{tarball} ) )
	{
		return 0;
	}
	#my $filename = $self->{session}->get_repository->get_id . ".zip";
	my $filename = "files.zip";
	my $filesize = -s $self->{processor}->{tarball};

	EPrints::Apache::AnApache::header_out(
			$self->{session}->get_request,
			"Content-Disposition: attachment; filename=$filename; Content-Length: $filesize;"
			);

	return 1;
}

sub export
{
	my( $self ) = @_;

	binmode(STDOUT);
	my $file = $self->{processor}->{tarball};
	seek($file,0,0);
	open(HANDLE,$file);
	while(sysread(HANDLE, my $buffer, 4096))
	{
		print $buffer;
	}
	unlink($file);
}

sub export_mimetype
{
	my( $self ) = @_;

	return "application/zip";
}

sub render
{
	my( $self ) = @_;

	return $self->{session}->make_doc_fragment;
}

sub redirect_to_me_url
{
	my( $self ) = @_;

	return undef;
}

1;

