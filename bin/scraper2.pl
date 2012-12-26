#!/usr/bin/perl

use common::sense;

use URI;
use URI::Escape;
use JSON;
use Try::Tiny;
use Web::Scraper;
use Data::Dumper;

# Pages with the list of shows
my @showlist_urls = (
    "http://animal.discovery.com/tv/tv-shows.html",
    "http://animal.discovery.com/tv/tv-shows-tab-02.html"
    );

my $BASE_URI = 'http://animal.discovery.com/';

# ?num=24&page=0&filter=clip%2Cplaylist%2Cfullepisode&tpl=dds%2Fmodules%2Fvideo%2Fall_assets_grid.html&feedGroup=video
# Order is important
my $episodes_additional_options = '?num=24&page=0&filter=clip%2Cplaylist%2Cfullepisode&tpl=dds%2Fmodules%2Fvideo%2Fall_assets_grid.html&feedGroup=video';

# Get list of shows

my $showlist_scraper = scraper {
    process "ul li #list-item", "shows[]" => sub {
        my $show_data = shift;
        my $show_info_scraper = scraper {
            process "#list-image a", show_title => '@title';
            process "#list-image a", link_to_show => sub {
                    my $tag = shift;
                    return URI->new_abs( $tag->attr('href'), $BASE_URI );
                };
            process "#list-image img", show_thumb => sub {
                    my $tag = shift;
                    return URI->new_abs( $tag->attr('src'), $BASE_URI );
                };
            process "#list-text", show_desc => 'TEXT';
            process "#list-image a", episodes => sub {
                    # Collect series
                    my $tag = shift;
                    my @episodes = ();
                    my $episodes_list_url = URI->new_abs( $tag->attr('href'), $BASE_URI );
                    # Get link to episodes list from special field
                    my $episodes_url_scraper = scraper {
                        process "#all-videos .module-videos-all", episodes_url => '@data-service-uri';
                    };
                    my $res = $episodes_url_scraper->scrape( $episodes_list_url );
                    return
                        unless length( $res->{episodes_url} );
                    my $episodes_fulllist_url = URI->new_abs( $res->{episodes_url}, $BASE_URI );
                    $episodes_fulllist_url->query( $episodes_additional_options );
                    # Dirty solution to pack in one cycle
                    my $next_page = -1;
                    my $next_page_url = $episodes_fulllist_url->clone();
                    my $episode_list_scraper = scraper {
                        process ".all-grid-inner .item", 'episodes[]' => scraper {
                            process ".thumbnail a img", episode_thumb => '@src';
                            process ".thumbnail a .playlist-clip-count", playlist_size => 'TEXT';
                            process ".details a", episode_link => '@href', episode_title => 'TEXT';
                        };
                        process ".pagination li", 'pages[]' => scraper {
                            process 'a', link => '@onclick', text => 'TEXT';
                        };
                    };
                    while ( $next_page ) {
                        if ( $next_page > 0 ) {
                            $next_page_url = $episodes_fulllist_url->as_string();
                            $next_page_url =~ s/page=\d+/page=$next_page/igmx;
                            $next_page_url = URI->new( $next_page_url );
                        }
                        
                        my $res = $episode_list_scraper->scrape( $next_page_url );
                        foreach my $episode ( @{ $res->{episodes} } ) {
                            # Fetch episodes or sub-episodes depending on playlist flag
                            if ( $episode->{playlist_size} =~ /^\d/ ) {
                                
                            } else {
                                my $one_episode_scraper = scraper {
                                    process "script", 'js[]' => sub {
                                        my $tmp = $_->as_HTML();
                                        my ( $clips_js ) = $tmp =~ /(\"clips\":\s+\[[^]]+\])/ismx;
                                        my $clip_data = try {
                                            from_json( "{".$clips_js."}" )
                                        } catch {
                                            {
                                                clips => [
                                                    {
                                                        m3u8 => undef,
                                                        duration => undef,
                                                        thumbnailURL => undef
                                                    }
                                                ]    
                                            }
                                        };
                                        return {
                                            m3u => $clip_data->{clips}[0]{m3u8},
                                            duration => $clip_data->{clips}[0]{duration},
                                            episode_thumb => $clip_data->{clips}[0]{thumbnailURL}
                                        };
                                    };
                                    
                                };
                                my $res = $one_episode_scraper->scrape( $episode->{episode_link} );
                            }
                            push @episodes, $episode;
                        }
                        
                        $next_page = undef;
                        foreach my $page ( @{ $res->{pages} } ) {
                            ( $next_page ) = $page->{link} =~ /,(\d+),/igmx
                                if ( $page->{link} and $page->{text} =~ /NEXT/igmx );
                        }
                    }

                    return { episodes => \@episodes };
                };
        };
        return $show_info_scraper->scrape( $show_data );
    }
};

## MAIN

sub _scrape {
    foreach my $url ( @showlist_urls ) {
        my $res = $showlist_scraper->scrape( URI->new( $url ) );
        print to_json( $res )."\n";
    }

}

_scrape();

exit();