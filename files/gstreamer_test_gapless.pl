#!/usr/bin/perl
use strict;
use warnings;
use GStreamer -init;

my ($file1,$file2)=grep m/[a-z]/i, @ARGV;
my ($skip)=grep m/^-?\d+$/, @ARGV;
$skip=-5 unless defined $skip;
die "usage : $0 [seconds] file1 file2\n seconds is -5 by default\n" unless -e $file1 && -e $file2;

my $loop = Glib::MainLoop -> new(undef, 0);
my $player = GStreamer::ElementFactory -> make(playbin2 => "player");
$player->set(uri => Glib::filename_to_uri $file1, "localhost");
$player->signal_connect(about_to_finish => \&about_to_finish);

Glib::Timeout->add(100,\&UpdateTime);

print "Playing: $file1\n";

$player -> set_state("playing") or die "Could not start playing";
$loop -> run();
$player -> set_state("null");


sub about_to_finish
{	$player->set(uri => Glib::filename_to_uri $file2, "localhost");
	print "\nsoon playing: $file2\n";
}

sub UpdateTime
{	my ($result,$state,$pending)=$player->get_state(0);
	return 1 if $result eq 'async';
	if ($skip)
	{	warn "skipping to $skip s\n";
		$player->seek(1,'time','flush',($skip>0 ? 'set' :'end'), $skip*1_000_000_000,'none',0);
		$skip=0;
		return 1;
	}
	return 1 if $state ne 'playing';
	my $query=GStreamer::Query::Position->new('time');
	if ($player->query($query))
	{	my (undef, $position)=$query->position;
		printf STDERR "\r %.1f s", $position/1_000_000_000;
	}
	return 1;
}
