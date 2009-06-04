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
                              $q->th({id => 'query'},'Query'),
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

#
# NO HTML BEYOND THIS POINT
#

sub get_dbh {
    return DBI->connect($dbi_str, 
                        $db_user, 
                        $db_pass 
                       );
    # ping it? see if it's the proxy or the real thing?
}

sub get_stats {    
    my $dbh = get_dbh();
        
    # cope nicely if that's not supported or empty
    my $stats = $dbh->selectall_hashref('show stats','module : line : called');
    
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
