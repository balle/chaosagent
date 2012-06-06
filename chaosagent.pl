#!/usr/bin/perl
#
# Chaos Agent 0.7
#
# Programmed by Bastian Ballmann
# Balle@chaostal.de
#
# License: GPLv2
#
# Last update: 21.11.2007
#

###[ Loading modules ]###

use Yahoo::Search;          # Yahoo API
use Weather::Cached;        # Weather.com API
use LWP::UserAgent;         # Let's surf the web
use LWP::Simple qw(get);    #
use XML::Simple;            # Parsing XML configs
use XML::RSS;               # Create RSS feed
use XML::RSS::Feed;         # Parsing RSS feeds
use Getopt::Long;           # Parsing parameter
use strict;                 # Be strict!
use Data::Dumper;


###[ Configuration ]###

# weather.com partner id
my $weather_id = "1034470227";

# weather.com license key
my $weather_license = "765546bba5d0c258";

# Browser timeout
my $timeout = 10;

# Where to find festival
my $festival = "/usr/bin/festival";

# Temp directory
my $tmpdir = "/tmp/chAosAgent";


###[ MAIN PART ]###

# Version number
my $version = "0.7";

# Dont buffer output
$| = 1;

# Set secure umask
umask(066);

# Set important environment variables
$ENV{'PATH'} = '';
$ENV{'BASH_ENV'} = '';
$ENV{'IFS'} = '\r\n';

my %opt;
my $agent;
my %urls_found = {};

# Need help?
usage() if $ARGV[0] eq "--help" or scalar(@ARGV) == 0;

# Get parameter
GetOptions("f|file=s"     => \$opt{'file'},
			"o|output=s"  => \$opt{'output'},
			"d|download"  => \$opt{'download'},
			"r|rss=s"     => \$opt{'rss'},			
			"s|silent"    => \$opt{'silent'},
			"q|quite"     => \$opt{'quite'},
			"S|summary"   => \$opt{'summary'},
			"w|weather=s" => \$opt{'weather'},
) or usage();

$opt{'silent'} = 1 if $opt{'quite'};

print "\n-" . "=-" x 23 . "\n";
print "Chaosagent $version\n";
print "Programmed by Bastian Ballmann\n";
print "-" . "=-" x 23 . "\n\n";
speak("Hello. I am your chaos agent.") unless $opt{'silent'};

# Read query file
if(-f $opt{'file'})
{
	my $queries = XMLin($opt{'file'}, ForceArray => 1) or die "Cannot read $opt{'file'}!\n$!\n";

	# Search Yahoo!
	print "\n-" . "=-" x 23 . "\n";
	print "Yahoo Search\n";
	print "-" . "=-" x 23 . "\n\n";
	my %searched_urls = yahoo_search($queries);

	# Write resulting URLs as RSS feed
	my $result_feed = new XML::RSS(version => '1.0');

	# Report found urls
	foreach my $query (keys %searched_urls)
	{
		foreach my $result ( @{ $searched_urls{ $query } } )
		{
			while(my ($url, $title) = each %{ $result })
			{
				print "Found $url\n";
				speak("Found $title") unless $opt{'quite'};

				$result_feed->add_item(title => $title,
	 			    		       link  => $url);
			}
		}
	}

	# Fetch urls?
	if(-d $opt{'output'} && $opt{'download'})
	{
		$result_feed->save("$opt{'output'}/search_results.xml");

		# Get a browser object
		$agent = LWP::UserAgent->new(agent => 'Chaos Agent $version');
		$agent->timeout($timeout);

		speak("Fetching urls. Please wait...") unless $opt{'silent'};

		print "\n\n-" . "=-" x 23 . "\n";
		print "Fetching URLs\n";
		print "-" . "=-" x 23 . "\n\n";

		my %fetched_urls = get_urls(%searched_urls);
		dump_urls($opt{'output'}, %fetched_urls);
	}
}

# Get weather data?
if($opt{'weather'} ne "")
{
	print "\n\n-" . "=-" x 23 . "\n";
	print "Looking up weather data\n";
	print "-" . "=-" x 23 . "\n\n";

	get_weather_data($opt{'weather'});
}

# Read RSS news?
if(-f $opt{'rss'})
{
	my $feeds = XMLin($opt{'rss'}, ForceArray => 1) or die "Cannot read $opt{'rss'}!\n$!\n";

	print "\n\n-" . "=-" x 23 . "\n";
	print "Reading RSS news\n";
	print "-" . "=-" x 23 . "\n\n";

	rss_reader($feeds);
}

speak("Thanks for all the fish. Bye!") unless $opt{'silent'};



###[ Subroutines ]###

# Fetch URLs
# Parameter: Hash URLs
# Return value: Hash (key url, value HTTP::Response object)
sub get_urls
{
    my %urls = @_;
	my %responses;

    while(my ($query, $results) = each %urls)
    {
		foreach my $result (@{$results})
		{
			foreach my $url (keys %{ $result })
			{
			    # Get the page
			    chomp $url;
			    print "GET $url... ";
			    my $response = $agent->get($url);
			    print "[Done]\n";

				$responses{$url} = $response;
			}
	    }
    }

    return %responses;
}

# Dump URLs content to disk
# Parameter: outputdir, Hash URLs (key search term, value array ref of urls)
sub dump_urls
{
	my $outputdir = shift;
	my %fetched_urls = @_;

	foreach my $response (values %fetched_urls)
	{
		next unless $response->is_success;

		my $tmpfile = $response->request->uri;
		$tmpfile =~ s/http\:\/\///;
		$tmpfile =~ s/\/$//g;
		$tmpfile =~ s/\//\_/g;
		$tmpfile =~ s/\:/\_/g;

		open(OUT, ">$outputdir/$tmpfile") or die "Cannot write $outputdir/$tmpfile!\n$!\n";
		map { print OUT; } $response->content;
		close(OUT);
	}
}

# Use Yahoo to search for queries
# Parameter: query xml obj
# Return value: hash URLs (key search term, value array ref of urls)
sub yahoo_search
{
    my $queries = shift;
    my %urls = ();

	foreach my $group (@{ $queries->{'group'} })
	{
		foreach my $query (@{ $group->{'query'} })
		{
			print "Searching Yahoo for $query\n";
			speak("Searching Yahoo for $query") unless $opt{'silent'};

			my @urls = ();
		    my @Results = Yahoo::Search->Results(Doc => $query,
		                                         AppId => "ChaosAgent",
		                                         # The following args are optional.
		                                         # (Values shown are package defaults).
		                                         Mode         => 'all', # all words
		                                         Start        => 0,
		                                         Count        => 10,
		                                         Type         => 'any', # all types
		                                         AllowAdult   => 1, 
		                                         AllowSimilar => 0, # no dups, please
		                                         Language     => undef,
		                                         );


		    foreach my $Result (@Results)
		    {
				# Skip it?
				my $skipme;
			    map { $skipme = 1 if $Result->Summary =~ /$_/i; } @{ $group->{'skip_keyword'} };
			    map { $skipme = 1 if $Result->Title =~ /$_/i; } @{ $group->{'skip_keyword'} };
			    map { $skipme = 1 if $Result->Url =~ /$_/i; } @{ $queries->{'skip_url'} };
			    map { $skipme = 1 if $Result->Url =~ /$_$/i; } @{ $queries->{'skip_filetype'} };
			    next if $skipme;

				# URL already known?
				next if exists $urls_found{$Result->Url};

				# Otherwise save it
				$urls_found{$Result->Url} = 1;
				my %result;

				if($opt{'summary'})
				{
					$result{ $Result->Url } = $Result->Summary;
				}
				else
				{
					$result{ $Result->Url } = $Result->Title;
				}

				push @urls, \%result;
		     }

		     $urls{$query} = \@urls;
		}
	}

    return %urls;
}


# Read filtered rss news
# Parameter: rss xml obj
sub rss_reader
{
	my $feeds = shift;
	my $new_feed = new XML::RSS(version => '1.0');
	my $counter = 0;

	speak("Time for news! Let's fetch some RSS.") unless $opt{'silent'};

	mkdir($tmpdir) unless -d $tmpdir;

	foreach my $group (@{ $feeds->{'group'} })
	{
		foreach my $feed (@{ $group->{'feed'} })
		{
			my $reader = XML::RSS::Feed->new(url => $feed,
											 tmpdir => $tmpdir);

			$reader->parse( get( $reader->url ) );

			foreach my $news ($reader->late_breaking_news)
			{
				# Skip it?
				my $skipme = 1;
			    map { $skipme = 0 if $news->headline =~ /$_/i; } @{ $group->{'keyword'} };
			    next if $skipme;

				unless($opt{'quite'})
				{
					print "[" . $news->url . "] " . $news->headline . "\n";
				}

				speak($news->headline) unless $opt{'quite'};

				$new_feed->add_item(title => $news->headline,
									link  => $news->url,
									description => $news->description);

				$counter++;
			}
		}
	}

	if(-d $opt{'output'})
	{
		$new_feed->save("$opt{'output'}/latest_rss_news.xml");
	}

	if($counter == 0)
	{
		speak("Cannot find any new news out there.") unless $opt{'quite'};
	}
}

# Get weather data from weather.com
# Parameter: string (location)
# Return value: nothing
sub get_weather_data
{
	my $location = shift;

	speak("Looking up weather data for $location.") unless $opt{'silent'};

    my %params = (
                       'cache'      => $tmpdir,
                       'partner_id' => $weather_id,
                       'license'    => $weather_license,
                       'place'      => $location,
    );

	my $weather = Weather::Cached->new(%params);
	my $found_locations = $weather->search( $location ) or exit_program("Cannot find location $location.");

	if(scalar( keys %{ $found_locations } ) == 0)
	{
		speak("$location? Where the fuck is $location. Cannot find anything.") unless $opt{'quite'};
	}
	elsif(scalar( keys %{ $found_locations } ) > 1)
	{
		speak("Found " . scalar( keys %{ $found_locations } ) . " locations for $location.")  unless $opt{'quite'};
	}

	foreach (keys %{ $found_locations })
	{
		my $w = $weather->get_weather($_);
		my $l_name = $w->{'loc'}->{'dnam'};
		$l_name =~ s/\///g;

		print Dumper($w);
		speak($l_name . ".") unless $opt{'quite'};

		if(-d $opt{'output'})
		{
			$l_name =~ s/\,/\-/g;
			$l_name =~ s/\s/\_/g;

			open(OUT, ">$opt{'output'}/" . $l_name . "_weather.xml");
			print OUT "<?xml version='1.0'?>\n";
			print OUT "<weather>\n";
			print OUT "<location>" . $w->{'loc'}->{'dnam'} . "</location>\n";
		}

		if($w->{'loc'}->{'sunr'} ne "")
		{
			$w->{'loc'}->{'sunr'} =~ s/\:/ /;
			speak("Sun rise at " . $w->{'loc'}->{'sunr'} . ".") unless $opt{'quite'};
			print OUT "<sunrise>" . $w->{'loc'}->{'sunr'} . "</sunrise>\n" if $opt{'output'};
		}

		if($w->{'loc'}->{'suns'} ne "")
		{
			$w->{'loc'}->{'suns'} =~ s/\:/ /;
			speak("Sun set at " . $w->{'loc'}->{'suns'} . ".") unless $opt{'quite'};
			print OUT "<sunset>" . $w->{'loc'}->{'suns'} . "</sunset>\n" if $opt{'output'};
		}

		if($w->{'cc'}->{'t'} ne "")
		{
			speak("Weather is " . $w->{'cc'}->{'t'}) unless $opt{'quite'};
			print OUT "<conditions>" . $w->{'cc'}->{'t'} . "</conditions>\n" if $opt{'output'};
		}
		else
		{
			speak("Cannot find any weather data. I am sorry...") unless $opt{'quite'};
			print OUT "<conditions>unknown</condition>\n" if $opt{'output'};
		}

		if($w->{'cc'}->{'tmp'} ne "")
		{
			speak("Temperature " . $w->{'cc'}->{'tmp'} . " degree.") unless $opt{'quite'};
			print OUT "<temp>" . $w->{'cc'}->{'tmp'} . " C</temp>\n" if $opt{'output'};
		}
		else
		{
			print OUT "<temp>unknown</temp>\n";
		}

		if($opt{'output'})
		{
			print OUT "</weather>\n";
			close(OUT);
		}
	}
}

# Text to speech via festival
# Parameter: string
sub speak
{
	my $msg = shift;
	$msg =~ s/([;<>\*\|'&\$#\(\)\[\]\{\}:"])//g;

	system("echo '$msg' | $festival --tts");
}

sub usage
{
	print "Usage: $0 \n";
	print "-f(ile) <query_file>\n";
	print "-o(utput) <dir>\n";
	print "-d (download urls)\n";
	print "--silent (only report news)\n";
	print "--quite (dont say a word!)\n";
	print "--summary (read search result summary)\n";
	print "--rss <rss_file>\n";
	print "-w(eather) <location>\n";

	exit(0);
}

sub exit_program
{
	my $msg = shift;

	print "$msg\n";
	speak($msg);

	exit(1);
}

# EOF dude.