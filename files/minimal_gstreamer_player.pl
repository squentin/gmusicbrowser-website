#!/usr/bin/perl
use strict;
use warnings;
use GStreamer -init;

for my $file (@ARGV)
{	my $loop = Glib::MainLoop -> new(undef, 0);
	my $player = GStreamer::ElementFactory -> make(playbin => "player");
	$player -> set(uri => Glib::filename_to_uri $file, "localhost");

	print "Playing: $file\n";

	$player -> set_state("playing") or die "Could not start playing";
	$loop -> run();
	$player -> set_state("null");
}

