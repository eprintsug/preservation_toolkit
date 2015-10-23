package EPrints::Plugin::Event::DroidScan;

@ISA = qw( EPrints::Plugin::Event );

use strict;

sub droidscan
{
	my( $self, $doc_id ) = @_;

	my $repository = $self->{repository};
	
	return undef unless( $repository->get_conf( "invocation", "droid" ) );
	
	my $doc = new EPrints::DataObj::Document( $repository, $doc_id );
	
	return unless need_to_scan( $doc );

	foreach my $file (@{$doc->get_value( "files" )})
	{
		$self->update_pronom_identity($file);
	}

	EPrints::DataObj::EventQueue->create_unique( $repository , {
			pluginid => "Event::Update_Pronom_File_Counts",
			action => "main",
	});

	return undef;
}

sub scan_repository
{
	
	my( $self ) = @_;

	my $repository = $self->{repository};

	my $dataset = $repository->get_dataset( "eprint" );

	my $format_files = {};

	$dataset->map( $repository, sub {
		my( $repository, $dataset, $eprint ) = @_;
		
		foreach my $doc ($eprint->get_all_documents)
		{
			my $doc_id = $doc->id;
			foreach my $file (@{($doc->get_value( "files" ))})
			{
				my $puid = $file->get_value( "pronomid" );
				if (!defined $puid) {
					EPrints::DataObj::EventQueue->create_unique( $repository , {
		                                pluginid => "Event::DroidScan",
                		                action => "droidscan",
                                		params => [$doc_id],
		                        });	
				}
			}
		}
	} );

	return undef;
}


sub need_to_scan
{
	my ( $document ) = @_;
	
	return undef unless $document;
	
	my $eprint = $document->get_parent();
	return undef unless $eprint;

#	my $eprint_status = $eprint->get_value('eprint_status');
#	return undef unless ($eprint_status eq "buffer" or $eprint_status eq "archive");

	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "issmallThumbnailVersionOf" )));
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "ismediumThumbnailVersionOf" )));
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "ispreviewThumbnailVersionOf" )));
	return undef if ($document->has_related_objects( EPrints::Utils::make_relation( "isIndexCodesVersionOf" )));
	
	return 1;
}

sub update_pronom_identity
{
	my( $self, $file ) = @_;

	my $session = $self->{session};

	my $fh = $file->get_local_copy();
	return unless defined $fh;

	my $droid_file_list = File::Temp->new( SUFFIX => ".xml");
	my $file_list_xml = $session->make_doc_fragment();
	my $file_collection = $session->make_element("FileCollection", xmlns=>"http://www.nationalarchives.gov.uk/pronom/FileCollection");
	my $identification_file = $session->make_element("IdentificationFile", IdentQuality=>"Not yet run");
	$identification_file->appendChild($session->render_data_element(4,"FilePath",$fh));
	$file_collection->appendChild($identification_file);
	$file_list_xml->appendChild($file_collection);
	print $droid_file_list EPrints::XML::to_string($file_list_xml);

	my $droid_xml = File::Temp->new( SUFFIX => ".xml");
	my $sig = $session->get_repository->get_conf( "droid_sig_file" );
#	print STDERR "Scanning $fh\n\n";
	$session->get_repository->exec( "droid",
			SOURCE => $droid_file_list,
			TARGET => substr("$droid_xml",0,-4), # droid always adds .xml
			SIGFILE => "$sig", 
			);

	if ( -e $droid_xml ) {
		my $doc = EPrints::XML::parse_xml("$droid_xml");

		my $PUID_node = ($doc->getElementsByTagName( "PUID" ))[0];
		my $PUID;
		my $name;
		my $version;
		my $mimetype;
		if (defined $PUID_node)
		{
			$PUID = EPrints::Utils::tree_to_utf8($PUID_node);
			my $classification_date_node = ($doc->getElementsByTagName( "DateCreated" ))[0];
			my $classification_date = EPrints::Utils::tree_to_utf8($classification_date_node);
			my $classification_status_node = ($doc->getElementsByTagName( "Status" ))[0];
			my $classification_status = EPrints::Utils::tree_to_utf8($classification_status_node);
			$file->set_value( "pronomid", $PUID );
			$file->set_value( "classification_quality", $classification_status );
			$file->set_value( "classification_date", $classification_date );
			$file->commit;
			my $name_node = ($doc->getElementsByTagName( "Name" ))[0];
			$name = defined $name_node ?
				EPrints::Utils::tree_to_utf8($name_node) :
				"";
			my $version_node = ($doc->getElementsByTagName( "Version" ))[0];
			$version = defined $version_node ?
				EPrints::Utils::tree_to_utf8($version_node) :
				"";
			my $mimetype_node = ($doc->getElementsByTagName( "MimeType" ))[0];
			$mimetype = defined $mimetype_node ?
				EPrints::Utils::tree_to_utf8($mimetype_node) :
				"";
		} 
		else 
		{
			$PUID = "UNKNOWN";
			my $classification_date_node = ($doc->getElementsByTagName( "DateCreated" ))[0];
			my $classification_date = EPrints::Utils::tree_to_utf8($classification_date_node);
			my $classification_status = "No Match in Pronom";
			$file->set_value( "pronomid", $PUID );
			$file->set_value( "classification_quality", $classification_status );
			$file->set_value( "classification_date", $classification_date );
			$file->commit;
			$name = "UNKNOWN (DROID found no classification match)";
			$mimetype = "";
		}	
		my $pronom_data = $session->get_repository->get_dataset("pronom")->get_object($session, $PUID);
		if (defined $pronom_data)
		{
			$pronom_data->set_value("name", $name);
			$pronom_data->set_value("version", $version);
			$pronom_data->set_value("mime_type", $mimetype);
			$pronom_data->commit;
		}
		else
		{
			$pronom_data = $session->get_repository->get_dataset("pronom")->create_object($session,{pronomid=>$PUID,name=>$name,version=>$version,mime_type=>$mimetype});
		}
		EPrints::XML::dispose($doc);
	}
}
