#!/usr/bin/perl

use common::sense;

use URI;
use URI::Escape;
use JSON;
use Try::Tiny;
use Web::Scraper;
use Data::Dumper;
use Coro;
use Coro::LWP;
use EV;
use WWW::Mechanize;

# Convert URI::http object to JSON
sub URI::http::TO_JSON {
    return shift->as_string;
}

# Pages with the list of shows
my $showlist_url = 'http://tlc.howstuffworks.com/tv/tv-shows.htm';

my $BASE_URI = 'http://tlc.howstuffworks.com/';

my $showlist_channel = new Coro::Channel;
my $shows_channel = new Coro::Channel;
my $logging_channel = new Coro::Channel;

sub _log {
    my $msg = shift;
    
    return $logging_channel->put( '['.$Coror::current->{desc}.'] '.$msg );
}

#sub __get_showlist($$) {
#    my $channel = shift;
#    my $start_url = shift;
#    
#    return async {
#        $Coror::current->{desc} = 'Showlist scraper, '.$start_url;
#        my %tmp;
#        my $showlist_scraper = scraper {
#            process ".line .textRight ul li a", "links[]" => sub {
#                    my $link = $_->attr('href');
#                    $channel->put( URI->new( $link ) )
#                        unless exists $tmp{$link};
#                    $tmp{$link} = 1;
#                };
#        };
#        _log('Start');
#        $showlist_scraper->scrape( $start_url );
#        $channel->shutdown;
#        _log('Done');
#        return;
#    }
#}

sub __get_showlist($$) {
    my $start_url = shift;
    my $options = shift;
    
    return async {
        $Coror::current->{desc} = 'Showlist: '.$start_url;
        my %tmp;
        my @res;
        my @coros;
        my $showlist_scraper = scraper {
            process ".line .textRight ul li a", "links[]" => sub {
                    my $link = $_->attr('href');
                    unless ( exists $tmp{$link} ) {
                        my $coro = __scrape_shows( URI->new( $link ), {} );
                        push @coros, $coro;
                    }
                    $tmp{$link} = 1;
                };
        };
        _log('Start');
        say Dumper(\@coros);
        $showlist_scraper->scrape( $start_url );
        foreach my $coro (@coros) {
            say $coro->desc;
            push @res, $coro->join;
        }
        _log('Done');
        return wantarray ? @res : \@res;
    }
}

#sub __scrape_shows($$) {
#    my $channel = shift;
#    my $url = shift;
#    
#    return async {
#        $Coror::current->{desc} = 'Show scraper, '.$url;
#        my $show_scraper = scraper {
#            process "ul li.marginTop1", "shows[]" => sub {
#                my $html = $_->as_HTML;
#                my $show_details_scraper = scraper {
#                    process "div.media a.img", "show_url" => '@href', "show_thumb" => sub {
#                        return $_->look_down( _tag => 'img' )->attr('src');
#                    };
#                    process "div.media div.bd a", "show_title" => "TEXT";
#                    process "div.media div.bd p", "show_description" => "TEXT";
#                };
#                $channel->put( $show_details_scraper->scrape( $html ) );
#                
#            }
#        };
#        _log('Show start');
#        $show_scraper->scrape( $url );
#        _log('Show done');
#        return;
#    };
#}

sub __scrape_shows($$) {
    my $url = shift;
    my $options = shift;
    
    return async {
        $Coror::current->{desc} = 'Show: '.$url;
        my $show_scraper = scraper {
            process "ul li.marginTop1", "shows[]" => sub {
                my $html = $_->as_HTML;
                my $show_details_scraper = scraper {
                    process "div.media a.img", "show_url" => '@href', "show_thumb" => sub {
                        return $_->look_down( _tag => 'img' )->attr('src');
                    };
                    process "div.media div.bd a", "show_title" => "TEXT";
                    process "div.media div.bd p", "show_description" => "TEXT";
                };
                my $res =  $show_details_scraper->scrape( $html );
                return wantarray ? @{ $res->{shows} } : $res->{shows};
            }
        };
        _log('Start');
        $show_scraper->scrape( $url );
        _log('Done');
        return;
    };
}

# Start logging channel
async {
    while ( my $msg = $logging_channel->get() ) {
        say $msg;
    }
}

# Start showlist scrapping queue
#async {
#    __get_showlist( $showlist_channel, URI->new( $showlist_url ) );
#    __scrape_shows( $shows_channel, URI->new($showlist_url) );
#    
#    my @showlist = ( URI->new($showlist_url) );
#    while ( my $link = $showlist_channel->get() ) {
#        push @showlist, $link;
#        __scrape_shows( $shows_channel, $link );
#    }
#    return;
#};

# Shows scraper
#async { 
#    my @shows;
#    while ( my $show = $shows_channel->get() ) {
#        push @shows, $show;
#        say Dumper($show);
#    }
#    say Dumper( \@shows );
#    return;
#};

my $res = __get_showlist( URI->new( $showlist_url ), { } );
say Dumper( $res->join );


EV::loop;
