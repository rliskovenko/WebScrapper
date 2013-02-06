#!/usr/bin/perl

use common::sense;

use List::Util qw/min max/;
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

# get-videos params
my $get_videos = 'http://tlc.howstuffworks.com/ajax/get-videos?display=grid&filter%5B%5D=clip&filter%5B%5D=playlist&filter%5B%5D=fullepisode&sort=date+desc&dwsPage=PPPPPP&cid=DDDDDD&templateCode=VideoHub&num=18';

# Pages with the list of shows
my $showlist_url = 'http://tlc.howstuffworks.com/tv/tv-shows.htm';

my $BASE_URI = 'http://tlc.howstuffworks.com/';

sub __get_showlist($$) {
    my $start_url = shift;
    my $storage = shift;
    
    return async {
        $Coror::current->{desc} = 'Showlist: '.$start_url;
        my %tmp;
        my @res;
        my @coros;
        push @coros, __scrape_shows( $start_url, $storage );
        my $showlist_scraper = scraper {
            process ".line .textRight ul li a", "links[]" => sub {
                    my $link = $_->attr('href');
                    unless ( exists $tmp{$link} ) {
                        my $coro = __scrape_shows( URI->new( $link ), $storage );
                        push @coros, $coro;
                    }
                    $tmp{$link} = 1;
                };
        };
        $showlist_scraper->scrape( $start_url );
        $_->join
            foreach @coros;
        return;
    }
}

sub __scrape_shows($$) {
    my $url = shift;
    my $storage = shift;

    return async {
        $Coror::current->{desc} = 'Shows: '.$url;
        my @coros;
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
                $res->{episodes} = [];
                # Some links directs to videos itself, some need an extraction
                $res->{videos_url} = $res->{show_url};
                my @path_segments = URI->new( $res->{show_url} )->path_segments();
                if ( $path_segments[-1] !~ /video/igsmx ) {
                    __scrape_videos_url( URI->new( $res->{show_url} ), $res )->join;
                    # Handle unstarted but announced shows
                    return
                        unless $res->{videos_url};
                }
                my $coro = __scrape_episodes( URI->new( $res->{videos_url} ), $res->{episodes} );
                push @coros, $coro;
                push @$storage, $res;
            }
        };
        $show_scraper->scrape( $url );
        $_->join
            foreach @coros;
        return;
    };
}

sub __scrape_videos_url($$) {
    my $url = shift;
    my $storage = shift;
    
    return async {
        $Coror::current->{desc} = 'Videos: '.$url;
        my $videos_url_scraper = scraper {
            process "div.ft ul li", 'urls[]' => scraper {
                process "a", 'url' => '@href', 'text' => 'TEXT';
            }
        };
        my $res = $videos_url_scraper->scrape( $url );
        my @videos_url = grep { $_->{text} =~ /VIDEO/igmsx } @{ $res->{urls} };
        $storage->{videos_url} = $videos_url[0]->{url};
        return;
    }
}

sub __scrape_episodes($$) {
    my $url = shift;
    my $storage = shift;
    
    return async {
        $Coror::current->{desc} = 'Episodes: '.$url;
        my @coros;
        my @pages;
        __scrape_episodes_paging( $url, \@pages )->join;
        foreach my $page (@pages) {
            my $mech = WWW::Mechanize->new();
            my $res = $mech->get( $page );
            my $text = from_json( $res->decoded_content() );
            my %hrefs;
            my $episode_list_scraper = scraper {
                process "div.videoTile a", 'link[]' => sub {
                    my $href = $_->attr('href');
                    unless ( exists( $hrefs{$href} ) ) {
                        my $coro = __scrape_one_episode( $href, $storage );
                        push @coros, $coro;
                        $hrefs{$href} = 1;
                    }
                };
            };
            $episode_list_scraper->scrape( "$text->{html}" );
        }
        $_->join
            foreach @coros;
        return;
    };
}

sub __scrape_one_episode($$) {
    my $url = shift;
    my $storage = shift;
    
    return async {
        $Coror::current->{desc} = 'Episode: '.$url;
        my $one_episode_scraper = scraper {
            process 'script', 'js[]' => sub {
                my $tmp = $_->as_HTML();
                $tmp =~ /\"clips\":\s+\[\s+({.+?})/ismx;
                return
                    unless $1;
                my $clips_js = '{ "clips": '.$1.' }';
                ## Unescape "\'"
                $clips_js =~ s{\\([^"])}{$1}igmsx;
                
                my $clip_data = try {
                    from_json( $clips_js )
                } catch {
                    say "<!-- Bad JSON: >>$clips_js<< !-->"; 
                };
                my $clip_info = $clip_data->{clips};
                my $ret = {
                            m3u => $clip_info->{m3u8},
                            duration => $clip_info->{duration},
                            episode_thumb => URI->new( $clip_info->{thumbnailURL} ),
                            episode_title => $clip_info->{episodeTitle},
                            episode_desc => $clip_info->{videoCaption},
                            episode_url => $url,
                    };
                foreach (keys %$ret) {
                    if ( ! $ret->{$_} ) {
                        say "<!-- UNDEF: $_ -> $url !-->";
                    }
                }
                push @{ $storage }, $ret;
            }
        };
        try {
            $one_episode_scraper->scrape( URI->new( $url ) );
        } catch {
            say "<!-- Error fetching URL: $url !-->"
        }
    };
}

sub __scrape_episodes_paging($) {
    my $url = shift;
    my $storage = shift;
    
    return async {
        $Coror::current->{desc} = 'Episodes paging: '.$url;
        
        my @pages;
        my $episodes_paging_scraper = scraper {
            process 'script', 'js[]' => sub {
                my $script = $_->as_HTML();
                ## No videos
                return
                    if ( index($script, 'get-videos') < 0 );
                $script =~ /\bfunction\s+load\(\)\s+({.+?}(?![;)}]))/igmsx;
                my $function = $1;
                $function =~ /_params.cid=(\d+)/igmsx;
                my $cid = $1;
                my $paging_url = $get_videos;
                $paging_url =~ s/=D{6}/=$cid/igmsx;
                $paging_url =~ s/=P{6}/=0/igmsx;
                my $mech = WWW::Mechanize->new();
                my $res = $mech->get( $paging_url );
                my $text = from_json( $res->decoded_content() );
                my $pages_scraper = scraper {
                    process 'div ul li a', 'nums[]' => 'TEXT'
                };
                $res = $pages_scraper->scrape( $text->{html} );
                my $num = 1;
                my @page_numbers;
                push @page_numbers, 0;
                while ( $num >= min( @{$res->{nums}} ) && $num < max (@{$res->{nums}}) ) {
                    push @page_numbers, $num;
                    $num++;
                }
                foreach my $page_num (@page_numbers) {
                    my $page_url = $get_videos;
                    $page_url =~ s/=D{6}/=$cid/igmsx;
                    $page_url =~ s/=P{6}/=$page_num/igmsx;
                    push @$storage, $page_url;
                }
            }
        };
        $episodes_paging_scraper->scrape( $url );
        return;
    }
}

my @res;
__get_showlist( URI->new( $showlist_url ), \@res )->join;

say to_json( \@res, { pretty => 1, relaxed => 1, allow_blessed => 1, convert_blessed => 1 } );

