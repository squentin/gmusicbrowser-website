#!/usr/bin/perl
# Script to import lastplay, rating, playcount and labels from amarok to gmusicbrowser.
# gmusicbrowser must be running and the music files must be in its library.
# Only tested with a SQLite amarok collection, other database will probably work if
# the $dbs value below is corrected.

use strict;
use warnings;
use DBI;
my $dbfile=$_[0] || $ENV{HOME}.'/.kde/share/apps/amarok/collection.db';
my $dbs="dbi:SQLite:dbname=$dbfile";
# my $dbs="dbi:Pg:dbname=$dbname"		#postgresql
# my $dbs="DBI:mysql:database=$database"	#mysql
# $dbs.=";host=$host;port=$port"
my $user='';
my $password='';
my $dbh=DBI->connect($dbs,$user,$password, {RaiseError =>1, AutoCommit=>0});

use Net::DBus;
my $bus= Net::DBus->session;
my $service = $bus->get_service("org.gmusicbrowser");
my $object = $service->get_object("/org/gmusicbrowser","org.gmusicbrowser");

#tested with :
#	Database Version 35
#	Database Stats Version 12
#	Database Devices Version 1

{	my $sth=$dbh->prepare('SELECT * FROM admin');
	$sth->execute or die "Can't execute statement: $DBI::errstr";
	while ( my @ver=$sth->fetchrow_array )
	{	warn "@ver\n";
	}
}

my @devices;
{	my $sth=$dbh->prepare('SELECT id,lastmountpoint FROM devices');
	$sth->execute or die "Can't execute statement: $DBI::errstr";
	while ( my ($id,$url)=$sth->fetchrow_array )
	{	$devices[$id]=$url;
	}
}

{	my $sth=$dbh->prepare('SELECT deviceid,url,accessdate,rating,playcounter FROM statistics');
	$sth->execute or die "Can't execute statement: $DBI::errstr";
	my $error=$count=0;
	while ( my ($device,$url,$accessdate,$rating,$playcounter)=$sth->fetchrow_array )
	{	my $e;
		$url=~s#^\.#$devices[$device]#;
		$object->Set([$url,'lastplay',$accessdate])	or $e++ and warn "error setting 'lastplay' to $accessdate for file $url\n";
		$object->Set([$url,'rating',$rating]) 		or $e++ and warn "error setting 'rating' to $rating for file $url\n";
		$object->Set([$url,'playcount',$playcounter])	or $e++ and warn "error setting 'playcount' to $playcounter for file $url\n";
		if ($e) {$error++} else {$count++}
	}
	print "Imported lastplay/playcount/rating for $count files. ". ($error ? "$error files with error" : "no error"). "\n";
}

{	my $sth=$dbh->prepare('SELECT tags_labels.deviceid, tags_labels.url, labels.name FROM tags_labels JOIN labels ON tags_labels.labelid=labels.id'); #what is labels.type ?
	$sth->execute or die "Can't execute statement: $DBI::errstr";
	my %labels;
	my $error=$count=0;
	while ( my ($device,$url,$label)=$sth->fetchrow_array )
	{	$url=~s#^\.#$devices[$device]#;
		push @{$labels{$url}},$label;
	}
	for my $url (keys %labels)
	{	my $label=join "\t",@{ $labels{$url} };
		$object->Set([$url,'label',$label])	and $count++	or $error++ and warn "error setting 'label' to [$label] for file $url\n";
	}
	print "Imported labels for $count files. ". ($error ? "$error files with error" : "no error"). "\n";
}

$dbh->disconnect;

