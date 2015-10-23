package EPrints::Plugin::Event::Update_Pronom_File_Counts;

@ISA = qw( EPrints::Plugin::Event );

use strict;

sub main
{
	my( $self ) = @_;

	my $repository = $self->{repository};
	
	my $pronom_data = $repository->get_dataset("pronom")->get_object($repository, "Unclassified");
	if (!defined $pronom_data)
	{
		$pronom_data = $repository->get_dataset("pronom")->create_object($repository,{pronomid=>"Unclassified",name=>"Unclassified Objects"});
	}
	
	$self->reset_pronom_cache();
	
	$self->update_file_count();
	
#	$self->update_risk_scores();

	return undef;
	
}

sub reset_pronom_cache
{
	my( $self ) = @_;

	my $repository = $self->{repository};

	my $dataset = $repository->get_dataset( "pronom" );

        $dataset->map( $repository, sub {
                my( $repository, $dataset, $pronoms ) = @_;

                foreach my $pronom_data ($pronoms)
                {
			$pronom_data->set_value("file_count",0);
			$pronom_data->commit;
                }
        } );	

}

sub update_file_count
{
	
	my( $self ) = @_;

	my $repository = $self->{repository};

	my $dataset = $repository->get_dataset( "eprint" );

	my $format_files = {};

	$dataset->map( $repository, sub {
		my( $repository, $dataset, $eprint ) = @_;
		
		foreach my $doc ($eprint->get_all_documents)
		{
			foreach my $file (@{($doc->get_value( "files" ))})
			{
				my $puid = $file->get_value( "pronomid" );
				$puid = "" unless defined $puid;
				push @{ $format_files->{$puid} }, $file->get_id;
			}
		}
	} );
	foreach my $format (keys %{$format_files})
	{
		my $count = $#{$format_files->{$format}}+1;
		my $pronom_data = $repository->get_dataset("pronom")->get_object($repository, $format);
		if (!defined $pronom_data)
		{
			$pronom_data = $repository->get_dataset("pronom")->get_object($repository, "Unclassified");
		}
		$pronom_data->set_value("file_count",$count);
		$pronom_data->commit;
	}
}

=pod
sub update_risk_scores
{	
	my( $repository ) = @_;

	my $doc;
	my $risks_url;
	my $available;
	my $soap_error = "";
	my $unstable = $repository->get_conf( "pronom_unstable" );

	my $risk_xml = "http://www.eprints.org/services/pronom_risk.xml";
	
	eval 
	{
		$doc = EPrints::XML::parse_url($risk_xml);
	};
	if ($@) 
	{
		$risks_url = "http://nationalarchives.gov.uk/pronom/preservationplanning.asmx";
		$available = 1;
	} 
	else 
	{
		my $node; 
		if ($unstable eq 1) 
		{
			$node = ($doc->getElementsByTagName( "risks_unstable" ))[0];
		} 
		else 
		{
			$node = ($doc->getElementsByTagName( "risks_stable" ))[0];
		}
		$available = ($node->getElementsByTagName( "available" ))[0];
		$available = EPrints::Utils::tree_to_utf8($available);
		if ($available eq 1) 
		{
			$risks_url = ($node->getElementsByTagName( "base_url" ))[0];
			$risks_url = EPrints::Utils::tree_to_utf8($risks_url);
		} 
		else 
		{
			$risks_url = "";
		}
	}
	my @SOAP_ERRORS = "";
	use SOAP::Lite
		on_fault => sub { my($soap, $res) = @_;
			if( ref( $res ) ) {
				chomp( my $err = $res->faultstring );
				push( @SOAP_ERRORS, "SOAP FAULT: $err" );
			}
			else 
			{
				chomp( my $err = $soap->transport->status );
				push( @SOAP_ERRORS, "TRANSPORT ERROR: $err" );
			}
			return SOAP::SOM->new;
		};
	
	if (!($risks_url eq "")) 
	{
		$soap_error = "";
		my $dataset = $repository->get_dataset( "pronom" );
		$dataset->map($repository, sub 
				{
				my $record = $_[2];
				my $format = $record->get_value("pronomid");
				unless ($format eq "UNKNOWN" || $format eq "Unclassified") 
				{
				my $soap_data = SOAP::Data->name( 'PUID' )->attr({xmlns => 'http://pp.pronom.nationalarchives.gov.uk'});
				my $soap_value = SOAP::Data->value( SOAP::Data->name('Value' => $format) );
				my $soap = SOAP::Lite 
				-> on_action(sub { 'http://pp.pronom.nationalarchives.gov.uk/getFormatRiskIn' } )
				-> proxy($risks_url)
				-> call ($soap_data => $soap_value);
#					-> method (SOAP::Data->name('PUID' => \SOAP::Data->value( SOAP::Data->name('Value' => $format) ))->attr({xmlns => 'http://pp.pronom.nationalarchives.gov.uk'}) );

				my $result = $soap->result();

				foreach my $error (@SOAP_ERRORS) 
				{
				if ($soap_error eq "" && !($error eq "")) 
				{
				$soap_error = $error;
				}
				}
				if ($soap_error eq "") 
				{
					$record->set_value("risk_score",$result);
					$record->commit;
				}
				else 
				{
					print STDERR ("Format Risk Analysis Failed for format ".$format.": \n" . $soap_error . "\n");
				}
				}

				} );
	}
}
=cut
sub valid_document
{
	my ( $document ) = @_;

	return undef unless $document;
	my $eprint = $document->get_parent();
	return undef unless $eprint;
	my $eprint_status = $eprint->get_value('eprint_status');
	return undef unless ($eprint_status eq "buffer" or $eprint_status eq "archive");
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "issmallThumbnailVersionOf" )));
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "ismediumThumbnailVersionOf" )));
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "ispreviewThumbnailVersionOf" )));
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "isIndexCodesVersionOf" )));
	
	return 1;
}
