package QuantoView;

use strict;
use warnings;
use CGI qw/:standard/;

use DBI;
use DBD::mysql;

# add an option for different sort methods
# or just do that at table level?

# I suppose trunk should be optional
my $branch = 'trunk';
my $base_source_url = $ENV{BASE_SOURCE_URL};
my $dbi_str = $ENV{DBI};
my $db_user = $ENV{DBUSER};
my $db_pass = $ENV{DBPASS};
my $sort_field = 'times';

sub draw_stats {
    my $q = CGI->new();

    if (not ($dbi_str and $db_user and $db_pass)) {
	fail_no_vars($q);
    }

    if ($q->param('clear stats')) {
        clear_stats();        
    }

    my $table;
    my $stats = get_stats();
    foreach my $row (@{$stats}) {
        my $module = $row->{module};        
        if ($row->{uri}) {
            $module = '<a href='.$row->{uri}.'>'.$row->{module}.'</a>';            
        }
        
        $table .= $q->Tr($q->td([$module,
                                 $row->{line},
                                 $row->{called},
                                 $row->{times}
                                ]
                               ),
                         $q->td({id => 'time'},$row->{time_total}),
                         $q->td({id => 'time'},$row->{time_avg}),
                         $q->td({id => 'time'},$row->{time_max}),
                         $q->td({id => 'rows'},$row->{rows_total}),
                         $q->td({id => 'rows'},$row->{rows_avg}),
                         $q->td({id => 'rows'},$row->{rows_max}),
                         $q->td({id => 'query'},'<p></p><div class="toggle">'.
                                                $row->{query}.
                                                '</div>'),
                        )."\n";        
    }
    $table = $q->table({-border => 1},
                       $q->Tr($q->th({colspan => 4},''),
                              $q->th({id=>'time',colspan => 3},'Time (ms)'),
                              $q->th({id=>'rows',colspan => 3},'Rows'),
                              $q->th({id=>'query'},''),
                             ),
                       $q->Tr($q->th('Module'),
                              $q->th('Line'),
                              $q->th('Called'),
                              $q->th('Count'),
                              $q->th({id => 'time'},'Total'),
                              $q->th({id => 'time'},'Avg.'),
                              $q->th({id => 'time'},'Max'),
                              $q->th({id => 'rows'},'Total'),
                              $q->th({id => 'rows'},'Avg.'),
                              $q->th({id => 'rows'},'Max'),
                              $q->th({id => 'query'},'First Query'),
                             )."\n",
                       $table
                   );
    
    print $q->header();
    print '<div id="content"></div>';
    print $q->start_html(
        -title => 'Quanto!',
        -script=>[{ -src => 'http://ajax.googleapis.com/ajax/libs/jquery/1.3.1/jquery.min.js',
                  },
                  { -src => '/quanto.js',
                  }, 
                 ],        
        -style => {'src' => '/style.css'},
        -head  => meta({-http_equiv => 'refresh',
                        -content    => 30,
                       }
                      ),
    );
    
    print $q->start_form;
    print $q->submit('clear stats');
    print $q->end_form;
    print "\n";
        
    print $table;
    print $q->end_html;
}

sub fail_no_vars {
    my ($q) = @_;

    print $q->header();
    print '<div id="content"></div>';
    print $q->start_html(
        -title => 'Quanto Error!',
        -style => {'src' => '/style.css'},
    );
    print "<h1>Error!</h1>\n";
    print "<p>Quanto can't find the enrivronment variables to connect to the database.</p>\n";
    print "<p>You need to supply all of:\n";
    print $q->ul(['DBI','DBUSER','DBPASS']);
    print "</p>";
    print $q->end_html();

    exit(0);
}

sub fail_no_dbh {
    my ($dbi_errstr) = @_;

    my $q = CGI->new();

    print $q->header();
    print '<div id="content"></div>';
    print $q->start_html(
        -title => 'Quanto Error!',
        -style => {'src' => '/style.css'},
    );
    print "<h1>Error!</h1>\n";
    print "<p>When trying to connect to the database, Quanto got this error:</p>\n";
    print "<p><pre>$dbi_errstr</pre></p>";
    print "<p></p>\n";
    print "<p>Current settings are:\n";
    print $q->ul(['DBI='.$dbi_str,
		  'DBUSER='.$db_user,
		  'DBPASS='.$db_pass
		  ]);
    print "</p>";
    print $q->end_html();

    exit(0);
}

sub fail_do_show_stats {
    my ($dbi_errstr) = @_;

    my $probably_not_proxy = 0;
    if ($dbi_errstr =~ m/You have an error in your SQL syntax/) {
	$probably_not_proxy = 1;
    }

    my $q = CGI->new();

    print $q->header();
    print '<div id="content"></div>';
    print $q->start_html(
        -title => 'Quanto Error!',
        -style => {'src' => '/style.css'},
    );
    print "<h1>Error!</h1>\n";
    if ($probably_not_proxy) {
	print "<p>The mysql server didn't understand the 'show stats' command, are you sure Quanto is pointing at the proxy? Is the proxy running the quanto collector script? (e.g. mysql-proxy --proxy-lua-script=quanto/lua/quanto_collector.lua)</p>";

    }
    else {
	print "<p>When trying to run the 'show stats' command, Quanto got this error</p>\n";
	print "<p<pre>$dbi_errstr</pre></p>";
    }
    print "<p></p>\n";
    print "<p>Curret settings are:\n";
    print $q->ul(['DBI='.$dbi_str,
		  'DBUSER='.$db_user,
		  'DBPASS='.$db_pass
		  ]);
    print "</p>";
    print $q->end_html();

    exit(0);
}

#
# NO HTML BEYOND THIS POINT
#

sub get_dbh {
    my $dbh = DBI->connect($dbi_str, 
			   $db_user, 
			   $db_pass,
			   { RaiseError => 1}
			   );
    if (not $dbh) {
	fail_no_dbh($DBI::errstr);
    }
    
    # ping it? see if it's the proxy or the real thing?
   
    return $dbh;
}

sub get_stats {    
    my $dbh = get_dbh();
    
    my $stats;

    eval {
	$stats = $dbh->selectall_hashref('show stats','module : line : called');
    };
    if ($@) {
	if ($dbh->err) {
	    fail_do_show_stats($dbh->errstr);
	}
	else {
	    die $@;
	}
    }

    my @result;
    foreach my $key (keys %{$stats}) {
        my $row = $stats->{$key};
                        
        my %line;
        ($line{module},$line{line},$line{called}) = split('@', $row->{'module : line : called'});
        $line{times} = $row->{'times called'};
        $line{time_total} = $row->{'total time (ms)'};
        $line{time_avg} = $row->{'avg time (ms)'};
        $line{time_max} = $row->{'max time (ms)'};
        $line{rows_avg} = $row->{'row avg'};
        $line{rows_max} = $row->{'row max'};
        $line{rows_total} = $row->{'row count'};
        $line{query} = $row->{'query'};
                        
        $line{uri} =  make_uri($line{module}, $line{line});
        
        push @result, \%line;        
    }
    
    @result = sort {$b->{$sort_field} <=> $a->{$sort_field}} @result;

    return \@result;
}

sub clear_stats {
    my $dbh = get_dbh();
        
    # cope nicely if that's not supported or empty
    my $rv = $dbh->do('clear stats');
    $rv = $dbh->do('flush query cache');
}

sub make_uri {
    my ($module, $line) = @_;
    
    my $result = '';

    # maybe if you can't -e the .pm in the lib dir?
    # that would get rid of scripts too
    #
    # also if the local file is modified, then the link isn't going to help
    if (($module !~ /eval/) and (substr($module,0,1) ne '/')) {
        $result = $base_source_url.$module.'.pm#L'.$line;
    }
    
    return $result;    
}

##
1;
