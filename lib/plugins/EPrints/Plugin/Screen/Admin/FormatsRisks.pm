#######################################################
###                                                 ###
###    Preserv2/EPrints FormatsRisk Screen Plugin   ###
###                                                 ###
#######################################################
###                                                 ###
###     Developed by David Tarrant and Tim Brody    ###
###                                                 ###
###          Released under the GPL Licence         ###
###           (c) University of Southampton         ###
###                                                 ###
###        Install in the following location:       ###
###  eprints/perl_lib/EPrints/Plugin/Screen/Admin/  ###
###                                                 ###
#######################################################

package EPrints::Plugin::Screen::Admin::FormatsRisks;

@ISA = ( 'EPrints::Plugin::Screen' );

use strict;

sub new
{
	my( $class, %params ) = @_;

	my $self = $class->SUPER::new(%params);
	
	$self->{actions} = [qw/ formats_risks handle_upload get_plan delete_plan_docs recount/]; 
		
	$self->{appears} = [
		{ 
			place => "admin_actions_editorial", 
			position => 3000, 
		},
	];

	return $self;
}

sub can_be_viewed
{
	my( $self ) = @_;

	return $self->allow( "staff/eprint_search" );	
}

sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}

sub fetch_data
{
	my ( $plugin ) = @_;

	my $session = $plugin->{session};

	my $dataset = $session->get_repository->get_dataset( "pronom" );

	my $format_files = {};

	$dataset->map( $session, sub {
		my( $session, $dataset, $pronom_formats ) = @_;
		
		foreach my $pronom_format ($pronom_formats)
		{
			my $puid = $pronom_format->get_value( "pronomid" );
			$puid = "" unless defined $puid;
			if ($pronom_format->get_value("file_count") > 0) 
			{
				$format_files->{$puid} = $pronom_format->get_value("file_count");
			}
		}
	} );

#	$dataset = $session->get_repository->get_dataset( "file" );
#	my $list = $dataset->search(
#                filters => [
#                        { meta_fields => [qw( datasetid )], value => "document" },
#                        { meta_fields => [qw( pronomid )], value => "" , match => "EX" },
#                ],
#        );
#	my $count = $list->count;
#	if ($count > 0) {
#		$format_files->{"Unclassified"} = $count;
#	}
	
	return $format_files;
}

sub render
{
	my( $plugin ) = @_;

	my $session = $plugin->{session};

	my( $html , $table , $p , $span );

	$html = $session->make_doc_fragment;

	my $script = $plugin->{session}->make_javascript('
		function show(id) {
			var canSee = "inline";
			if(navigator.appName.indexOf("Microsoft") > -1){
				canSee = "inline";
			} else {
				canSee = "table-row";
			}
			$(id).style.display = canSee;
		}
		function hide(id) {
			if( !$(id) ) { return; }
			$(id).style.display = "none";
		}
		function plus(format) {
			hide(format + "_plus");
			show(format + "_minus");
			show(format + "_inner_row");
		}
		function minus(format) {
			show(format + "_plus");
			hide(format + "_minus");
			hide(format + "_inner_row");
		}
	');

	$html->appendChild($script);
	
	my $inner_panel = $plugin->{session}->make_element( 
			"div", 
			id => $plugin->{prefix}."_panel" );

	my $risks_unstable = $plugin->{session}->make_element(
			"div",
			align => "center"
			);	
	$risks_unstable->appendChild( $plugin->html_phrase("risk_reg_unstable") );

	my $br = $plugin->{session}->make_element(
			"br"
	);

	my $format_table;
	my $warning;
	my $doc;
	my $available;
	my $warning_width_table = $plugin->{session}->make_element(
		"table",
		id => "warnings",
		align=> "center",
		width => "620px"
	);
	my $wtr = $plugin->{session}->make_element( "tr" );
	my $warning_width_limit = $plugin->{session}->make_element( "td", width => "620px", align=>"center" );
	
	my $screen_id = "Screen::".$plugin->{processor}->{screenid};
        my $screen = $plugin->{session}->plugin( $screen_id, processor => $plugin->{processor} );

		
	my $buttons_div = $plugin->{session}->make_element(
			"div",
			align => "center",
			);
	my $recount_button = $screen->render_action_button({
                        action => "recount",
                        screen => $screen,
                        screen_id => $screen_id,
        });
	$buttons_div->appendChild($recount_button);
	$inner_panel->appendChild( $buttons_div );

	if( $session->get_repository->get_conf( "pronom_unstable" ) > 0) {
		$warning = $plugin->{session}->render_message("warning",
				$risks_unstable
				);
		$warning_width_limit->appendChild($warning);
	}
	$format_table = $plugin->get_format_risks_table( $warning_width_limit );

	$wtr->appendChild($warning_width_limit);
	$warning_width_table->appendChild($wtr);
	$inner_panel->appendChild($warning_width_table);
	$inner_panel->appendChild($format_table);
	$html->appendChild( $inner_panel );
	
	$html->appendChild( $plugin->render_hide_script );
	
	return $html;
}

sub render_hide_script {
	my( $plugin ) = @_;

	my @hides = ();
	my $dataset = $plugin->{session}->get_repository->get_dataset( "pronom" );

	my $medium_risk_boundary = $plugin->{session}->get_repository->get_conf( "medium_risk_boundary" );
	$dataset->map( $plugin->{session}, sub {
		my( $session, $dataset, $pronom_format ) = @_;
		
		my $result = $pronom_format->get_value("risk_score");
		my $format = $pronom_format->get_value("pronomid");

		if ($result <= $medium_risk_boundary) 
		{
			push @hides, 'hide("'.$format.'_0_minus");';
			push @hides, 'hide("'. $format.'_0_inner_row");';
			push @hides, 'hide("'.$format.'_1_minus");';
			push @hides, 'hide("'. $format.'_1_inner_row");';
		}
	} );

	push @hides, "";
	my $script = $plugin->{session}->make_javascript( join( "\n",@hides ) );
	return $script;
}

sub get_format_risks_table {
	
	my( $plugin, $message_element ) = @_;

	my $files_by_format = $plugin->fetch_data();

	if (%{$files_by_format} < 1) {
		my $unclassified = $plugin->{session}->make_element(
				"div",
				align => "center"
				);	
		$unclassified->appendChild( $plugin->html_phrase("no_objects") );
		my $warning = $plugin->{session}->render_message("warning", $unclassified);
		$message_element->appendChild($warning);	
	} 

	my $classified = 1;
	
	my $green = $plugin->{session}->make_element( "div", class=>"ep_msg_message", id=>"green" );
	my $orange = $plugin->{session}->make_element( "div", class=>"ep_msg_warning", id=>"orange" );
	my $red = $plugin->{session}->make_element( "div", class=>"ep_msg_error", id=>"red" );
	my $blue = $plugin->{session}->make_element( "div", class=>"ep_msg_other", id=>"blue" );
	#my $unclassified_orange = $plugin->{session}->make_element( "div", class=>"ep_msg_warning", id=>"unclassified_orange" );
	my $green_content_div = $plugin->{session}->make_element( "div", class=>"ep_msg_message_content" );
	my $orange_content_div = $plugin->{session}->make_element( "div", class=>"ep_msg_warning_content" );
	#my $unclassified_orange_content_div = $plugin->{session}->make_element( "div", class=>"ep_msg_warning_content" );
	my $red_content_div = $plugin->{session}->make_element( "div", class=>"ep_msg_error_content" );
	my $blue_content_div = $plugin->{session}->make_element( "div", class=>"ep_msg_other_content" );

	my $heading_red = $plugin->{session}->make_element( "h1", style=> "text-align: center;");
	$heading_red->appendChild( $plugin->html_phrase("high_risk") );
	$red_content_div->appendChild( $heading_red );
	my $heading_orange = $plugin->{session}->make_element( "h1", style=> "text-align: center;");
	$heading_orange->appendChild( $plugin->html_phrase("medium_risk") );
	$orange_content_div->appendChild( $heading_orange );
	my $heading_green = $plugin->{session}->make_element( "h1", style=> "text-align: center;");
	$heading_green->appendChild( $plugin->html_phrase("low_risk") );
	$green_content_div->appendChild( $heading_green );
	my $heading_blue = $plugin->{session}->make_element( "h1", style=> "text-align: center;");
	$heading_blue->appendChild( $plugin->html_phrase("no_scores") );
	$blue_content_div->appendChild( $heading_blue );
	
	my $green_count = 0;
	my $orange_count = 0;
	my $red_count = 0;
	my $blue_count = 0;

	my $max_count = 0;	
	my $max_width = 300;

	my $green_format_table = $plugin->{session}->make_element( "table", width => "100%");
	my $orange_format_table = $plugin->{session}->make_element( "table", width => "100%");
	my $red_format_table = $plugin->{session}->make_element( "table", width => "100%");
	my $blue_format_table = $plugin->{session}->make_element( "table", width => "100%");
	
	my $format_table = $blue_format_table;
	
	my $pronom_error_message = "";
	foreach my $format (sort { $files_by_format->{$b} <=> $files_by_format->{$a} } keys %{$files_by_format})
	{
		my $color = "blue";
		my $result;
		my $format_name = "";
		my $format_code = "";
		my $format_version = "";
		
		my $pronom_data = $plugin->{session}->get_repository->get_dataset("pronom")->get_object($plugin->{session}, $format);
		
		if (defined($pronom_data)) {
			$result = $pronom_data->get_value("risk_score");
			$format_name = $pronom_data->get_value("name");
			$format_version = $pronom_data->get_value("version");
		}

		my $high_risk_boundary = $plugin->{session}->get_repository->get_conf( "high_risk_boundary" );
		my $medium_risk_boundary = $plugin->{session}->get_repository->get_conf( "medium_risk_boundary" );


		if ($format eq "Unclassified" || $format eq "UNKNOWN" ) {
			$format_table = $red_format_table;
			$color = "red";
		} elsif ($result < 1) {
			$format_table = $blue_format_table;
			#$blue_count = $blue_count + 1;
			$color = "blue";
		} elsif ($result <= $high_risk_boundary) {
			$format_table = $red_format_table;
			#$red_count = $red_count + 1;
			$color = "red";
		} elsif ($result > $high_risk_boundary && $result <= $medium_risk_boundary) {
			$format_table = $orange_format_table;
			#$orange_count = $orange_count + 1;
			$color = "orange";
		} elsif ($result > $medium_risk_boundary) {
			$format_table = $green_format_table;
			#$green_count = $green_count + 1;
			$color = "green";
		} else {
			$format_table = $blue_format_table;
			#$blue_count = $blue_count + 1;
			$color = "blue";
		}
	
		my $count = $files_by_format->{$format};
		if ($max_count < 1) {
			$max_count = $count;
		}

		if ($format eq "" || $format eq "NULL") {
			$format_name = "Not Classified";
			$classified = 0;
		}

		if ($format_name eq "") {
			$format_name = $format;
		}

		my $search_format;	
		if ($format eq "Unclassified") {
			$search_format = "";
		} else {
			$search_format = $format;
		}

		my $other_row;
		my $format_count = 1;
		my $migrated_row;
		my $migrated_count = 0;

	
		if ($result <= $medium_risk_boundary && !($color eq "blue"))
		{
#			($other_row,$format_count) = $plugin->get_detail_row($search_format,$format,0);
#			($migrated_row,$migrated_count) = $plugin->get_detail_row($search_format,$format,1);
			$format_count = $count;
			if ($format eq "Unclassified" && $format_count > 0) {
				$classified = 0;
			}
			if ($result <= $high_risk_boundary && $format_count > 0) {
				$red_count++;
			} elsif ($result <= $medium_risk_boundary && $format_count > 0) {
				$orange_count++;
			}
			if ($migrated_count > 0) {
				$green_count++;
			}
		} else {
			$format_count = $count;
			if ($format_count > 0 && $color eq "blue") {
				$blue_count++;
			} elsif ($format_count > 0) {
				$green_count++;
			}
		}
		#print STDERR "COUNTS $green_count, $orange_count, $red_count, $blue_count\n\n";
		my $format_panel_tr = $plugin->get_format_panel($format_name,$format,$format_version,$format_count,$max_count,$max_width,$color,$result,$medium_risk_boundary,0);
		if ($format_count > 0) {
			$format_table->appendChild( $format_panel_tr );
			if (defined $other_row) {
				$format_table->appendChild( $other_row );
			}
		}

		my $preservation_panel_tr;
		if ($migrated_count > 0) {		
			$format_table = $green_format_table;
			$preservation_panel_tr = $plugin->get_format_panel($format_name,$format,$format_version,$migrated_count,$max_count,$max_width,$color,$result,$medium_risk_boundary,1);
			$format_table->appendChild( $preservation_panel_tr );
			if (defined $migrated_row) {
				$format_table->appendChild( $migrated_row );
			}
		}

	}

	my $ret = $plugin->{session}->make_doc_fragment;

	if (!($pronom_error_message eq "")) {
		my $pronom_error_div = $plugin->{session}->make_element(
			"div",
			align => "center"
			);	
		$pronom_error_div->appendChild( $plugin->{session}->make_text($pronom_error_message ));

		my $warning = $plugin->{session}->render_message("warning",
			$pronom_error_div
		);
		$ret->appendChild($warning);
		
	}

	$green_content_div->appendChild($green_format_table);
	$orange_content_div->appendChild($orange_format_table);
	$red_content_div->appendChild($red_format_table);
	$blue_content_div->appendChild($blue_format_table);
	if ($green_count > 0 || $orange_count > 0 || $red_count > 0) {
		$green->appendChild( $green_content_div );
		$orange->appendChild( $orange_content_div );
		$red->appendChild( $red_content_div );
	}
	if ($red_count > 0) { $ret->appendChild($red) };
	if ($orange_count > 0) { $ret->appendChild($orange) };
	if ($green_count > 0) { $ret->appendChild($green) };
	if ($blue_count > 0) {
		$blue->appendChild( $blue_content_div );
		$ret->appendChild($blue);
	}

	my $screen_id = "Screen::".$plugin->{processor}->{screenid};
        my $screen = $plugin->{session}->plugin( $screen_id, processor => $plugin->{processor} );

	if (!$classified) {
		my $unclassified = $plugin->{session}->make_doc_fragment();
		my $unclassified_div = $plugin->{session}->make_element(
				"div",
				align => "center"
				);	
		
		$unclassified_div->appendChild( $plugin->html_phrase("unclassified_warning_cron") );
		$unclassified->appendChild($unclassified_div);
		
		my $warning = $plugin->{session}->render_message("warning", $unclassified);
		$message_element->appendChild($warning);
	}

	my $pres_plans = $plugin->get_pres_plans_table();

	$ret->appendChild($pres_plans);

	return( $ret );
}

sub get_human_format_name {
	
	my ( $plugin,$format ) = @_;

	my $pronom_data = $plugin->{session}->get_repository->get_dataset("pronom")->get_object($plugin->{session}, $format);
	my $format_name;

	if (defined($pronom_data)) {
		$format_name = $pronom_data->get_value("name");
		my $format_version = $pronom_data->get_value("version");
		$format_name .= "(Version " . $format_version . ") ";
		return $format_name;
	}
	
	if ($format eq "" || $format eq "NULL") {
		$format_name = "Not Classified";
	}

	if ($format_name eq "") {
		$format_name = $format;
	}
	return $format_name;

}

sub get_pres_plans_table {
	
	my ( $plugin ) = @_;

	my $session = $plugin->{session};

	my $ret = $session->make_element("div",id=>"plans",align=>"center");
	
	my $dataset = $session->get_repository->get_dataset( "preservation_plan" );
	
	my $plan_count = 0;

	my $table = $session->make_element("table", width=>"100%");
	$ret->appendChild($table);
	my $table_th_row = $session->make_element("tr");
	$table->appendChild($table_th_row);

	my $table_header_1 = $session->make_element("th", width=>"10%");
	my $table_header_2 = $session->make_element("th", width=>"20%");
	my $table_header_3 = $session->make_element("th", width=>"50%");
	my $table_header_4 = $session->make_element("th", width=>"10%");
	my $table_header_5 = $session->make_element("th", width=>"10%");
	$table_th_row->appendChild($table_header_1);
	$table_th_row->appendChild($table_header_2);
	$table_th_row->appendChild($table_header_3);
	$table_th_row->appendChild($table_header_4);
	$table_th_row->appendChild($table_header_5);

	$table_header_1->appendChild($plugin->html_phrase("id"));
	$table_header_2->appendChild($plugin->html_phrase("import_date"));
	$table_header_3->appendChild($plugin->html_phrase("formats_affected"));
	$table_header_4->appendChild($plugin->html_phrase("quantity"));
	$table_header_5->appendChild($plugin->html_phrase("actions"));

	$dataset->map( $session, sub {
			my( $session, $dataset, $plans ) = @_;
			foreach my $preservation_plan ($plans)
			{
				$plan_count++;
				my $plan_id = $preservation_plan->get_id();
				
				my $table_row = $session->make_element("tr");
				$table->appendChild($table_row);
				my $table_td = $session->make_element("td", align=>"center");
				$table_row->appendChild($table_td);
				$table_td->appendChild($session->make_text($plan_id));	
			
				my $plan_date = $preservation_plan->get_value('import_date');
				$table_td = $session->make_element("td", align=>"center");
				$table_row->appendChild($table_td);
				$table_td->appendChild(EPrints::Time::render_date( $session, $plan_date ));	

				my $format_key = $preservation_plan->get_value('format');
				$format_key =~ s/_/\//;
				my $format_name = $plugin->get_human_format_name($format_key);
				
				$table_td = $session->make_element("td", align=>"center");
				$table_row->appendChild($table_td);
				$table_td->appendChild($session->make_text($format_name));	
				
				my $usage_count = $plugin->in_use($preservation_plan);
				my $b = $session->make_element("b");
				$b->appendChild($session->make_text($usage_count));
				
				$table_td = $session->make_element("td", align=>"center");
				$table_row->appendChild($table_td);
				$table_td->appendChild($b);	
				
				my $form = $session->render_form("POST");
				my $file_field = $session->make_element( 
						"input",
						name=> "file_path",
						value=> $preservation_plan->get_value('file_path'),
						type=> "hidden"
						);
				$form->appendChild($file_field);

				my $screen_id = "Screen::".$plugin->{processor}->{screenid} . "_get_plan";
				my $screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
				my $download_button = $screen->render_action_button(
						{
						action => "get_plan",
						screen => $screen,
						screen_id => $screen_id,
						} );
				$form->appendChild($download_button);

				$table_td = $session->make_element("td", align=>"center");
				$table_row->appendChild($table_td);
				$table_td->appendChild($form);	
			
				if ($usage_count > 0) {
					my $form2 = $session->render_form("POST");
					my $format_field = $session->make_element( 
							"input",
							name=> "format",
							value=> $format_key,
							type=> "hidden"
							);
					$form2->appendChild($format_field);

					$screen_id = "Screen::".$plugin->{processor}->{screenid};
					$screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
					my $delete_files_button = $screen->render_action_button(
							{
							action => "delete_plan_docs",
							screen => $screen,
							screen_id => $screen_id,
							} );
					$form2->appendChild($delete_files_button);

					$table_td->appendChild($form2);	
				} else {
					my $form2 = $session->render_form("POST");
	
					my $format_field = $session->make_element( 
							"input",
							name=> "format",
							value=> $format_key,
							type=> "hidden"
							);
					$form2->appendChild($format_field);

					$screen_id = "Screen::".$plugin->{processor}->{screenid} . "_delete_plan";
					$screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
					my $delete_button = $screen->render_action_button(
							{
							action => "delete_plan",
							screen => $screen,
							screen_id => $screen_id,
							} );
					$form2->appendChild($delete_button);
					$table_td->appendChild($form2);	
				}
				
			}
			});
	
	my $box = EPrints::Box::render(
			id => "preservation_plans_in_use",
			session => $plugin->{session},
			title => $plugin->html_phrase("preservation_plans_in_use"),
			collapsed => "false",
			content => $ret
			);

	if ($plan_count > 0) {
		return $box;
	} else {
		return $session->make_doc_fragment();
	}
	

}


sub get_format_panel {
	my ( $plugin, $format_name,$format,$format_version,$count,$max_count,$max_width,$color,$result,$medium_risk_boundary,$migrated) = @_;

	my $format_panel_tr = $plugin->{session}->make_element( 
			"tr", 
			id => $plugin->{prefix}."_".$format );

	my $format_details_td = $plugin->{session}->make_element(
			"td",
			width => "50%",
			style => "text-align : right;"
			);
	my $format_count_td = $plugin->{session}->make_element(
			"td",
			width => "50%",
			style => "text-align : left;"
			);
	my $pronom_output = $format_name . " ";
	if (trim($format_version) eq "") {
	} else {	
		$pronom_output .= "(Version " . $format_version . ") ";
	}
	my $format_bar_width = ($count / $max_count) * $max_width;
	if ($format_bar_width < 10) {
		$format_bar_width = 10;
	}
	my $format_count_bar = $plugin->{session}->make_element(
			"table",
#type => "submit",
			cellpadding => 0,
			cellspacing => 0,
			width => "100%",
			style => "background-color=$color;"
#value => ""
			);
	my $format_count_bar_tr = $plugin->{session}->make_element(
			"tr"
			);
	my $format_count_bar_td = $plugin->{session}->make_element(
			"td",
			width => $format_bar_width."px",
			style => "background-color: $color;"
			);
	my $format_count_bar_td2 = $plugin->{session}->make_element(
			"td",
			style => "padding-left: 2px"

			);

	$format_count_bar_td->appendChild( $plugin->{session}->make_text( "  " ) );
	$format_count_bar_td2->appendChild ( $plugin->{session}->make_text( " " .$count) );
	$format_count_bar_tr->appendChild( $format_count_bar_td ); 
	$format_count_bar_tr->appendChild( $format_count_bar_td2 ); 
	$format_count_bar->appendChild( $format_count_bar_tr );
	$format_details_td->appendChild ( $plugin->{session}->make_text( $pronom_output ) );

## PLUS MINUS
#
#	if ($result <= $medium_risk_boundary && !($color eq "blue") && !($format eq "Unclassified") && $migrated eq 0) 
#	{
#		$format_details_td->appendChild ( 
#				$plugin->render_plus_and_minus_buttons( $format,$migrated ) );
#	}
#
##

	$format_count_td->appendChild( $format_count_bar );
	$format_panel_tr->appendChild( $format_details_td );
	$format_panel_tr->appendChild( $format_count_td );
	return $format_panel_tr;
}

sub get_detail_row {
	
	my ( $plugin, $search_format, $format, $migrated ) = @_;

	my $session = $plugin->{session};

	my $other_row = $plugin->{session}->make_element(
			"tr"
			);
	my $other_column = $plugin->{session}->make_element(
			"td",
			colspan => 2
			);
	my $inner_table = $plugin->{session}->make_element(
			"table",
			style => "width: 100%;"
			);
	my $inner_row = $plugin->{session}->make_element(
			"tr",
			id => $format . "_" . $migrated . "_inner_row"
			);
	my $inner_column1 = $plugin->{session}->make_element(
			"td",
			style => "width: 62%;",
			valign => "top"
			);
	my $inner_column2 = $plugin->{session}->make_element(
			"td",
			style => "align: center;",
			valign => "top"
			);
	
	my $format_users = {};
	my $format_eprints = {};
	my $format_count;
	
	my $dataset = $session->get_repository->get_dataset( "file" );

	$search_format = $format;
	if ($format eq "Unclassified") {
		$search_format = "";
	}

	my $list;
	$list = $dataset->search(
		filters => [
			{ meta_fields => [qw( datasetid )], value => "document" },
			{ meta_fields => [qw( pronomid )], value => "$search_format", match => "EX" },
		],
	);

	if (!($search_format eq "") && $migrated eq 0) {
		$list->map( sub { 
			my $file = $_[2];	
			my $fileid = $file->get_id;
			my $document = $file->get_parent();
			return unless valid_document( $document );
			my $eprint = $document->get_parent();
			my $eprint_id = $eprint->get_value( "eprintid" );
			my $user = $eprint->get_user();
			my $user_id = $eprint->get_value( "userid" );
			if ((!($document->has_related_objects( EPrints::Utils::make_relation( "hasMigratedVersion" )))) && $migrated < 1) {
				push(@{$format_eprints->{$format}->{$eprint_id}},$fileid);
				push(@{$format_users->{$format}->{$user_id}},$fileid);
				$format_count++;
			} elsif (($document->has_related_objects( EPrints::Utils::make_relation( "hasMigratedVersion" ))) && $migrated > 0) {
				push(@{$format_eprints->{$format}->{$eprint_id}},$fileid);
				push(@{$format_users->{$format}->{$user_id}},$fileid);
				$format_count++;
			}
		} );

		my $table = $plugin->get_user_files($format_users,$format);
		my $eprints_table = $plugin->get_eprints_files($format_eprints,$format);
		my $preservation_action_table = $plugin->get_preservation_action_table($format,$migrated);

		$inner_column1->appendChild ( $eprints_table );
		$inner_column2->appendChild ( $table );
		$inner_column2->appendChild ( $session->make_element("br") );
		$inner_column2->appendChild ( $preservation_action_table );

		$inner_row->appendChild( $inner_column1 );
		$inner_row->appendChild( $inner_column2 );
		$inner_table->appendChild( $inner_row );
		$other_column->appendChild( $inner_table );
		$other_row->appendChild( $other_column );
	} else {
		$list->map( sub { 
			my $file = $_[2];	
			my $fileid = $file->get_id;
			my $document = $file->get_parent();
			return unless valid_document( $document );
			if ((!($document->has_related_objects( EPrints::Utils::make_relation( "hasMigratedVersion" )))) && $migrated < 1) {
				$format_count++;
			} elsif (($document->has_related_objects( EPrints::Utils::make_relation( "hasMigratedVersion" ))) && $migrated > 0) {
				$format_count++;
			}
		});
	}

	return ($other_row, $format_count);

}


sub valid_document
{
	my ( $document ) = @_;

	return 1;

	return undef unless ($document->isa("EPrints::DataObj::Document"));
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

sub render_plus_and_minus_buttons {
	my( $plugin, $format, $migrated ) = @_;

	my $imagesurl = $plugin->{session}->get_repository->get_conf( "rel_path" );
	my $plus_button = $plugin->{session}->make_element(
		"img",
		id => $format . "_" . $migrated . "_plus",
		onclick => 'plus("'.$format.'_'.$migrated.'")',
		src => "$imagesurl/style/images/plus.png",
		border => 0,
		alt => "PLUS"
	);
	my $minus_button = $plugin->{session}->make_element(
		"img",
		id => $format . "_" . $migrated . "_minus",
		onclick => 'minus("'.$format.'_'.$migrated.'")',
		src => "$imagesurl/style/images/minus.png",
		border => 0,
		alt => "MINUS"
	);
	my $f = $plugin->{session}->make_doc_fragment();
	$f->appendChild ( $plus_button );
	$f->appendChild ( $minus_button );
	return $f;
}

sub get_eprints_files
{
	my ( $plugin, $format_eprints, $format ) = @_;
	
	my $block = $plugin->{session}->make_element(
		"div",
		style=>"max-width: 500px; max-height: 400px; overflow: auto;"
		);
	#my $eprint_ids = %{$format_eprints}->{$format};
	#foreach my $eprint_id (keys %{$eprint_ids})
	my @eprint_ids = keys %{$format_eprints->{$format}};
	foreach my $eprint_id (@eprint_ids)
	{

		my @file_ids = @{$format_eprints->{$format}->{$eprint_id}};
		foreach my $file_id (@file_ids)
		{
			my $file = EPrints::DataObj::File->new(
                                $plugin->{session},
                                $file_id
                        );

			my $table = $plugin->{session}->make_element(
					"table",
					width => "100%"
                        );
			my $row1 = $plugin->{session}->make_element(
					"tr"
			);			
			my $col1 = $plugin->{session}->make_element(
					"td",
					style => "border: 1px dashed black; padding: 0.3em;",
					colspan => 2
			);
			my $file_url = $file->get_parent()->uri();			
			my $file_href = $plugin->{session}->make_element(
					"a",
					href => $file_url
			);
			my $bold = $plugin->{session}->make_element(
					"b"
			);
			$bold->appendChild( $plugin->{session}->make_text( $file->get_value("filename") ));	
			$file_href->appendChild( $bold );
			$col1->appendChild( $file_href );
			$col1->appendChild( $plugin->{session}->make_text(" (" . EPrints::Utils::human_filesize($file->get_value("filesize")) . ")"));
			$row1->appendChild( $col1 );
			$table->appendChild ( $row1 );
			my $row2 = $plugin->{session}->make_element(
					"tr"
			);			
			my $col2 = $plugin->{session}->make_element(
					"td",
					style => "border-right: 1px dashed black; border-left: 1px dashed black; padding: 0.3em;",
					colspan => 2
			);
			$bold = $plugin->{session}->make_element(
					"b"
			);
			$bold->appendChild( $plugin->{session}->make_text("Title: " ));
			$col2->appendChild( $bold );
			$col2->appendChild( $plugin->{session}->make_text($file->get_parent()->get_parent()->get_value( "title" )));
			$row2->appendChild( $col2 );
			$table->appendChild ( $row2 );
			my $row3 = $plugin->{session}->make_element(
					"tr"
			);			
			my $col3a = $plugin->{session}->make_element(
					"td",
					style => "border: 1px dashed black; padding: 0.3em;"
			);
			my $eprint_href = $plugin->{session}->make_element(
					"a",
					href => $file->get_parent()->get_parent()->uri()
			);
			$eprint_href->appendChild( $plugin->{session}->make_text($file->get_parent()->get_parent()->get_value( "eprintid" ) ));	
			$bold = $plugin->{session}->make_element(
					"b"
			);
			$bold->appendChild( $plugin->{session}->make_text("EPrint ID: " ));
			$col3a->appendChild( $bold );
			$col3a->appendChild( $eprint_href );
			my $col3b = $plugin->{session}->make_element(
					"td",
					style => "border-right: 1px dashed black; border-top: 1px dashed black; border-bottom: 1px dashed black; padding: 0.3em;"
			);
			$bold = $plugin->{session}->make_element(
					"b"
			);
			$bold->appendChild( $plugin->{session}->make_text("User: " ));
			$col3b->appendChild( $bold );
			my $eprint = $file->get_parent()->get_parent();
			my $user = $eprint->get_user();
			if( defined $user )
			{
				$col3b->appendChild( $user->render_description() );
			}
			else
			{
				$col3b->appendChild( $plugin->{session}->make_text( "Unknown User (ID: ".$eprint->get_value( "userid" ).")"));
			}
			$row3->appendChild( $col3a );
			$row3->appendChild( $col3b );
			$table->appendChild( $row3 );
			$block->appendChild($table);
			my $br = $plugin->{session}->make_element(
				"br"
			);
			$block->appendChild($br);
		}
	}
	
	return $block;
}

sub get_preservation_action_table
{
	my ( $plugin, $format, $migrated) = @_;
	
	my $session = $plugin->{session};
	my $outer_div = $session->make_element(
			"div",
			class => "ep_toolbox",
			style => "width: 300px;" 
			);
	my $inner_div = $session->make_element(
			"div",
			class => "ep_toolbox_content"
			);
	$outer_div->appendChild($inner_div);

	my $title_div = $session->make_element(
			"div",
			align => "center",
			style=> "font-size: 1.2em; font-weight: bold;"
			);
	$title_div->appendChild($plugin->html_phrase("preservation_actions"));
	$inner_div->appendChild($title_div);
	$inner_div->appendChild($plugin->{session}->make_element("hr"));

	my $p = $session->make_element(
			"p",
			style => "font-weight: bold;"
			);
	$p->appendChild($plugin->html_phrase("download_file_selection"));
	$inner_div->appendChild($p);
	
	my $screen_id = "Screen::".$plugin->{processor}->{screenid} . "_download";
	my $screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
	my $center_div = $session->make_element("div", align=>"center");
	my $form = $screen->render_form("POST");
	my $format_field = $session->make_element( 
			"input",
			name=> "format",
			value=> $format,
			type=> "hidden"
			);
	$form->appendChild($format_field);
	$form->appendText("No. of Files:");
	my $count_field = $session->make_element(
			"input",
			name=> "count",
			size=> 3,
			value=> 5
			);
	$form->appendChild($count_field);
	my $download_button = $screen->render_action_button(
			{
			action => "get_files",
			screen => $screen,
			screen_id => $screen_id,
			} );
	$form->appendText(" ");
	$form->appendChild( $download_button );
	$center_div->appendChild($form);
	$inner_div->appendChild($center_div);
	

	my $dataset = $session->get_repository->get_dataset( "preservation_plan" );
	my $orig_format = $format;
	$format =~ s/\//_/;
	$format =~ s/\\/_/;
	my $searchexp = EPrints::Search->new(
			session => $session,
			dataset => $dataset,
			filters => [
			{ meta_fields => [qw( format )], value => "$format", match => "EX" },
			],
			);

	my $list = $searchexp->perform_search;

	if ($session->get_repository->get_conf( "enable_preservation_actions" )) {
		$inner_div->appendChild($session->make_element("hr"));
		if ($list->count > 0) {
			my $file_path;
			$list->map( sub {
					my $preservation_plan = $_[2];
					$file_path = $preservation_plan->get_value("file_path");
					});
			$p = $session->make_element(
					"p",
					style => "font-weight: bold;"
					);
			$p->appendChild($plugin->html_phrase("download_pres_plan"));
			$inner_div->appendChild($p);

			my $download_div = $session->make_element("div", style=>"width: 300px;", align=>"center");
			my $form = $session->render_form("POST");
			$inner_div->appendChild($download_div);
			$download_div->appendChild($form);
			my $file_field = $session->make_element( 
					"input",
					name=> "file_path",
					value=> $file_path,
					type=> "hidden"
					);
			$form->appendChild($file_field);

			$screen_id = "Screen::".$plugin->{processor}->{screenid} . "_get_plan";
			$screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
			$download_button = $screen->render_action_button(
					{
					action => "get_plan",
					screen => $screen,
					screen_id => $screen_id,
					} );
			$form->appendChild($download_button);

			my $dataset = $session->get_repository->get_dataset( "preservation_plan" );			
			my $searchexp = EPrints::Search->new(
					session => $session,
					dataset => $dataset,
					filters => [
					{ meta_fields => [qw( format )], value => "$format", match => "EX" },
					],
					);

			my $list = $searchexp->perform_search;
			my $preservation_plan;
			$list->map( sub {
					$preservation_plan = $_[2];
					});
			if ($plugin->in_use($preservation_plan) < 1) {	
				$form = $session->render_form("POST");
				$download_div->appendChild($form);
				$form->appendChild($format_field);
				$screen_id = "Screen::".$plugin->{processor}->{screenid} . "_delete_plan";
				$screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
				my $msg = $plugin->phrase( "delete_plan_confirm" );
				my $delete_button = $screen->render_action_button(
						{
						action => "delete_plan",
						screen => $screen,
						screen_id => $screen_id,
#onclick => "if( window.event ) { window.event.cancelBubble = true; } return confirm(".EPrints::Utils::js_string($msg).");",
						} );
				$form->appendChild($delete_button);
			}
			$form = $session->render_form("POST");
			$download_div->appendChild($form);
## APPEND PLAN
			my $plan_field = $session->make_element( 
					"input",
					name=> "plan_id",
					value=> $preservation_plan->get_id(),
					type=> "hidden"
					);
			$form->appendChild($plan_field);
			my $format_field2 = $session->make_element( 
					"input",
					name=> "format",
					value=> $orig_format,
					type=> "hidden"
					);
			$form->appendChild($format_field2);
			$screen_id = "Screen::".$plugin->{processor}->{screenid} . "_enact_plan";
			$screen = $session->plugin( $screen_id, processor => $plugin->{processor} );
			my $enact_button = $screen->render_action_button(
					{
					action => "enact_plan",
					screen => $screen,
					screen_id => $screen_id,
					} );
			$form->appendChild($enact_button);
		} else {

			$p = $session->make_element(
					"p",
					style => "font-weight: bold;"
					);
			$p->appendChild($plugin->html_phrase("upload_pres_plan"));
			$inner_div->appendChild($p);

			my $upload_form = $session->render_form("POST");
			my $upload_div = $session->make_element("div", style=>"width: 300px;", align=>"center");
			my $f = $session->make_doc_fragment;

#$f->appendChild( $session->html_phrase( "Plugin/InputForm/Component/Upload:new_document" ) );

			my $ffname = $plugin->{prefix}."_first_file";
			my $file_button = $session->make_element( "input",
					name => $ffname,
					id => $ffname,
					type => "file",
					size=> 12,
					maxlength=>12,
					);
			my $upload_progress_url = $session->get_url( path => "cgi" ) . "/users/ajax/upload_progress";
			my $onclick = "return startEmbeddedProgressBar(this.form,{'url':".EPrints::Utils::js_string( $upload_progress_url )."});";
			my $add_format_button = $session->render_button(
					value => $session->phrase( "Plugin/InputForm/Component/Upload:add_format" ),
					class => "ep_form_internal_button",
					name => "_action_handle_upload",
					onclick => $onclick );
			$f->appendChild( $file_button );
			$f->appendChild( $session->make_element( "br" ));
			$f->appendChild( $add_format_button );
			my $progress_bar = $session->make_element( "div", id => "progress" );
			$f->appendChild( $progress_bar );

			my $script = $session->make_javascript( "EPJS_register_button_code( '_action_next', function() { el = \$('$ffname'); if( el.value != '' ) { return confirm( ".EPrints::Utils::js_string($session->phrase("Plugin/InputForm/Component/Upload:really_next"))." ); } return true; } );" );
			$f->appendChild( $script);
			$f->appendChild( $session->render_hidden_field( "screen", $plugin->{processor}->{screenid} ) );
			$f->appendChild( $session->render_hidden_field( "_action_handle_upload", "Upload" ) );
			$upload_div->appendChild($f);
			$upload_form->appendChild($upload_div);
			$format_field = $session->make_element( 
					"input",
					name=> "format",
					value=> $orig_format,
					type=> "hidden"
					);
			$upload_form->appendChild($format_field);
			$inner_div->appendChild($upload_form);
		}
	}	
	return $outer_div;
}

sub in_use 
{
	my ( $self, $preservation_plan ) = @_;

	my $session = $self->{session};

	my $dataset = $session->get_repository->get_dataset( "document" );

	my $pres_plan_uri = $preservation_plan->internal_uri();
	my $searchexp = EPrints::Search->new(
			session => $session,
			dataset => $dataset,
			filters => [
			{ meta_fields => [qw( relation_uri )], value => "$pres_plan_uri", match => "EX" },
			],
			);

	my $list = $searchexp->perform_search;
	if ($list->count() > 0) {
		return $list->count();
	} else {
		return 0;
	}

}

sub allow_delete_plan_docs {
	my ( $self ) = @_;

	return $self->allow( "config/view" );	
}

sub action_delete_plan_docs {

	my ( $self ) = @_;

	my $session = $self->{session};
	
	my $format = $self->{session}->param( "format" );

	$session->dataset( "event_queue" )->create_dataobj({
			pluginid => "Event::Delete_Plan_Docs",
			action => "delete_plan_docs",
			params => [$format],
			userid => $session->current_user(),
			});

	$self->{processor}->add_message(
			"message",
			$self->html_phrase( "delete_plan_docs_success" )
			);
	$self->{processor}->{screenid} = "Admin::FormatsRisks";
	
}

sub allow_recount 
{
	my ( $self ) = @_;
	
	return $self->allow( "config/view" );	
}

sub action_recount 
{
	my ( $self ) = @_;
	my $repository = $self->{repository};
	
	EPrints::DataObj::EventQueue->create_unique( $repository , {
		pluginid => "Event::Update_Pronom_File_Counts",
		action => "main",
	});

	$self->{processor}->add_message(
			"message",
			$self->html_phrase( "recount_success" )
			);
	$self->{processor}->{screenid} = "Admin::FormatsRisks";

		
		
}

sub allow_handle_upload 
{
	my ( $self ) = @_;
	
	return $self->allow( "config/view" );	
}

sub action_handle_upload
{
	my ( $self ) = @_;
	
	my $session = $self->{session};

	my $format = $self->{session}->param( "format" );
	my $orig_format = $format;
	$format =~ s/\//_/;
	$format =~ s/\\/_/;

	my $fname = $self->{prefix}."_first_file";

	my $fh = $session->get_query->upload( $fname );

	my $doc_path = $session->get_conf( "arc_path" ) . "/" . $session->get_id . "/documents/preservation_plans/";
	mkdir($doc_path);

	if( defined( $fh ) )
	{
		binmode($fh);
		my $tmpfile = File::Temp->new( SUFFIX => ".xml" );
		use bytes;

		while(sysread($fh,my $buffer, 4096)) {
			syswrite($tmpfile,$buffer);
		}

		my $dataset = $session->get_repository->get_dataset( "preservation_plan" );

		my $searchexp = EPrints::Search->new(
				session => $session,
				dataset => $dataset,
				filters => [
				{ meta_fields => [qw( format )], value => "$format", match => "EX" },
			],
		);
	
		my $list = $searchexp->perform_search;

		if ($list->count < 1) {
			my $output = $doc_path . $format . ".xml";
			rename($tmpfile,$output);
			my $plan_data = $session->get_repository->get_dataset("preservation_plan")->create_object($session,{plan_type=>"plato",file_path=>$output,format=>$format,import_date=>EPrints::Time::get_iso_timestamp()});
			my $plan_id = $plan_data->get_id();
			$plan_data->commit;
	
			$session->dataset( "event_queue" )->create_dataobj({
				pluginid => "Event::Migration",
				action => "migrate",
				params => [$orig_format, $plan_id],
				userid => $session->current_user(),
			});

			$self->{processor}->add_message(
                                "message",
                                $self->html_phrase( "upload_success" )
                                );
	                $self->{processor}->{screenid} = "Admin::FormatsRisks";
		} else {
			$self->{processor}->add_message(
                                "error",
                                $self->html_phrase( "plan_exists" )
                                );
	                $self->{processor}->{screenid} = "Admin::FormatsRisks";
		}
	
	}

}

sub get_user_files 
{
	my ( $plugin, $format_users, $format ) = @_;

	
	my $user_format_count_table = $plugin->{session}->make_element(
			"table",
			cellpadding => 1,
			style => "border: 1px solid black; width: 300px;",
			cellspacing => 0
			);
	my $user_format_count_tr = $plugin->{session}->make_element(
			"tr"
			);
	my $user_format_count_htr = $plugin->{session}->make_element(
			"tr"
			);
	my $user_format_count_th1 = $plugin->{session}->make_element(
			"th",
			align => "center",
			style => "font-size: 1em; font-weight: bold;"
			);
	my $user_format_count_th2 = $plugin->{session}->make_element(
			"th",
			align => "center",
			style => "font-size: 1em; font-weight: bold;"
			);
	$user_format_count_th1->appendChild( $plugin->{session}->make_text( "User" ));
	$user_format_count_th2->appendChild( $plugin->{session}->make_text( "No of Files" ));
	$user_format_count_htr->appendChild( $user_format_count_th1 );
	$user_format_count_htr->appendChild( $user_format_count_th2 );
	
	$user_format_count_table->appendChild( $user_format_count_htr );
	
	my $max_width=120;
	my $max_count = 0;



	my @user_ids = keys %{$format_users->{$format}};

	foreach my $user_id (sort  @user_ids)
	{
		my $count = $#{$format_users->{$format}->{$user_id}};
		$count++;
		if ($max_count < 1) {
			$max_count = $count;
		}
		my $user_format_count_tr = $plugin->{session}->make_element(
				"tr",
				);
		my $user_format_count_td1 = $plugin->{session}->make_element(
				"td",
				align => "right",
				style => "font-size: 0.9em; width: 120px;"
				);
		my $user = EPrints::DataObj::User->new( $plugin->{session}, $user_id );
		if( defined $user )
		{
			$user_format_count_td1->appendChild( $user->render_description() );
		}
		else
		{
			$user_format_count_td1->appendChild( $plugin->{session}->make_text( "Unknown User (ID: $user_id)"));
		}
		my $user_format_count_td2 = $plugin->{session}->make_element(
				"td",
				style => "width: 130px;"
				);
		my $file_count_bar = $plugin->{session}->make_element(
				"table",
				cellpadding => 0,
				cellspacing => 0,
				style => "width: 130px;"
				);
		my $file_count_bar_tr = $plugin->{session}->make_element(
				"tr"
				);
		my $file_bar_width = ($count / $max_count) * $max_width;
		if ($file_bar_width < 10) {
			$file_bar_width = 10;
		}
		my $file_count_bar_td1 = $plugin->{session}->make_element(
				"td",
				style => "width:".$file_bar_width."px;"
				);
		$file_bar_width = ($count / $max_count) * $max_width;
		if ($file_bar_width < 10) {
			$file_bar_width = 10;
		}
		my $file_count_bar_div = $plugin->{session}->make_element(
				"div",
				style => "width=".$file_bar_width."px; height: 10px; background-color: blue;"
				);
		my $file_count_bar_td2 = $plugin->{session}->make_element(
				"td",
				style => "padding-left: 2px;font-size: 0.8em;"
				);
		$file_count_bar_td1->appendChild( $file_count_bar_div );
		$file_count_bar_td2->appendChild( $plugin->{session}->make_text( $count ));
		$file_count_bar_tr->appendChild( $file_count_bar_td1 );
		$file_count_bar_tr->appendChild( $file_count_bar_td2 );
		$file_count_bar->appendChild( $file_count_bar_tr );
		$user_format_count_td2->appendChild( $file_count_bar );
		$user_format_count_tr->appendChild( $user_format_count_td1 );
		$user_format_count_tr->appendChild( $user_format_count_td2 );
		$user_format_count_table->appendChild( $user_format_count_tr );
	}
	return $user_format_count_table;	
}

#sub redirect_to_me_url
#{
#	my( $plugin ) = @_;
#
#	return undef;
#}

1;
