package File::Tail;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
$VERSION = '0.7';


# Preloaded methods go here.

use FileHandle;
use IO::Seekable;
use File::stat;
use Carp;
use Time::HiRes qw ( time sleep ); #import hires microsecond timers

sub interval {
    my $object=shift @_;
    if (@_) {
	$object->{interval}=shift;
	$object->{interval}=$object->{maxinterval} if 
	    $object->{interval}>$object->{maxinterval};
    }
    $object->{interval};
}

sub adjustafter {
    my $self=shift;
    $self->{adjustafter}=shift if @_;
    return $self->{adjustafter};
}

sub debug {
    my $self=shift;
    $self->{"debug"}=shift if @_;
    return $self->{"debug"};
}


sub errmode {
    my($self, $mode) = @_;
    my($prev) = $self->{errormode};
 
    if (@_ >= 2) {
        ## Set the error mode.
	defined $mode or $mode = '';
	if (ref($mode) eq 'CODE') {
	    $self->{errormode} = $mode;
	} elsif (ref($mode) eq 'ARRAY') {
	    unless (ref($mode->[0]) eq 'CODE') {
		croak 'bad errmode: first item in list must be a code ref';
		$mode = 'die';
	    }
	    $self->{errormode} = $mode;
	} else {
	    $self->{errormode} = lc $mode;
	}
    }
     $prev;
} 

sub errmsg {
    my($self, @errmsgs) = @_;
    my($prev) = $self->{errormsg};
 
    if (@_ > 0) {
        $self->{errormsg} = join '', @errmsgs;
    }
 
    $prev;
} # end sub errmsg
 
 
sub error {
    my($self, @errmsg) = @_;
    my(
       $errmsg,
       $func,
       $mode,
       @args,
       );
 
    if (@_ >= 1) {
        ## Put error message in the object.
        $errmsg = join '', @errmsg;
        $self->{"errormsg"} = $errmsg;
 
        ## Do the error action as described by error mode.
        $mode = $self->{"errormode"};
        if (ref($mode) eq 'CODE') {
            &$mode($errmsg);
            return;
        } elsif (ref($mode) eq 'ARRAY') {
            ($func, @args) = @$mode;
            &$func(@args);
            return;
        } elsif ($mode eq "return") {
            return;
	} elsif ($mode eq "warn") {
	    carp $errmsg;
        } else {  # die
	    croak $errmsg;
	}
    } else {
        return $self->{"errormsg"} ne '';
    }
} # end sub error


sub copy {
    my $self=shift;
    $self->{copy}=shift if @_;
    return $self->{copy};
}

sub nowait {
    my $self=shift;
    $self->{nowait}=shift if @_;
    return $self->{nowait};
}

sub method {
    my $self=shift;
    $self->{method}=shift if @_;
    return $self->{method};
}

sub input {
    my $self=shift;
    $self->{input}=shift if @_;
    return $self->{input};
}

sub maxinterval {
    my $self=shift;
    $self->{maxinterval}=shift if @_;
    return $self->{maxinterval};
}

sub resetafter {
    my $self=shift;
    $self->{resetafter}=shift if @_;
    return $self->{resetafter};
}

sub TIEHANDLE {
    my $ref=new(@_);
}

sub READLINE {
    $_[0]->read();
}

sub PRINT {
  $_[0]->error("PRINT makes no sense in File::Tail");
}

sub PRINTF {
  $_[0]->error("PRINTF makes no sense in File::Tail");
}

sub READ {
  $_[0]->error("READ not implemented in File::Tail -- use READLINE (<HANDLE>) instead");
}

sub GETC {
  $_[0]->error("GETC not (yet) implemented in File::Tail -- use READLINE (<HANDLE>) instead");
}

sub DESTROY {
  my($this) = shift(@_);
  undef $this->[0];
  undef $this;
  return undef;
}

sub new {
    my ($pkg)=shift @_;
    $pkg=ref($pkg) || $pkg;
    unless ($pkg) {
	$pkg="File::Tail";
    } 
    my %params;
    if ($#_ == 0)  {
	$params{"name"}=$_[0];
    } else {
	if (($#_ % 2) != 1) {
	    croak "Odd number of parameters for new";
	    return undef;
	}
	%params=@_;
    }
#    my $object=$pkg->SUPER::new();
    my $object = {};
    bless $object,$pkg;
    unless (defined($params{'name'})) {
	croak "No file name given. Pass filename as \"name\" parameter";
	return;
    }
    $object->input($params{'name'});
    $object->copy($params{'cname'});
    $object->method($params{'method'} || "tail");
#    $object->buffer("");
    $object->{buffer}="";
    $object->maxinterval($params{'maxinterval'} || 60);
    $object->interval($params{'interval'} || 10);
    $object->adjustafter($params{'adjustafter'} || 10);
    $object->errmode($params{'errmode'} || "die");
    $object->resetafter($params{'resetafter'} || 
			 ($object->maxinterval*$object->adjustafter));
    $object->{"debug"}=($params{'debug'} || 0);
    $object->{lastread}=0;
    if ($object->{"method"} eq "tail") {
#	reset_pointers($object);
	$object->reset_pointers;
    }
    return $object;
}

sub reset_pointers {
    my $object=shift @_;
    print "reseting after ".(time()-$object->{lastread})."s\n" if $object->{"debug"};

    my $st;

    my $oldhandle=$object->{handle};
    my $newhandle=FileHandle->new;

    unless (open($newhandle,"<".$object->input)) {
	if ($object->{'ignore_nonexistant'}) {
	    return;
	}
	$object->error("Error opening ".$object->input.": $!");
	return undef;
    }
    
    if (defined($oldhandle)) {
	# If file has not been changed since last OK read do not do anything
	$st=stat($newhandle);
	if (($st->mtime<$object->{lastread})) {
	    print "File not modified since last read. Reset skipped.\n" if $object->{"debug"};
	    return;
	}
	$object->{handle}=$newhandle;
	if ($st->ctime<$object->{lastread} or
	    $st->size<$object->{curpos}) {
	    $object->{curpos}=sysseek($object->{handle},0,SEEK_SET);
	} else {
	    $object->{curpos}=sysseek($object->{handle},0,SEEK_END);
	}
	close($oldhandle);
    } else {
	$st=stat($newhandle);
	$object->{handle}=$newhandle;
	$object->{curpos}=sysseek($object->{handle},0,SEEK_END);
#	$object->{lastread}=time;
	$object->{lastread}=$st->mtime; # for better estimate on initial read
    }
    
#    if (defined($object->{cname})) {
#	return $!="Error opening ".$object->{cname}.": $!",undef 
#	    unless open($object->{cname},">>".$object->{cname});
#    }
}


sub checkpending {
   my $object=shift @_;
   unless ($object->{handle}) {
       print "Trying to find previously nonexistant file\n" 
	   if $object->{"debug"};
       $object->reset_pointers;
       unless ($object->{handle}) { # This try did not open the file either
	   print "File does not yet exist\n" if $object->{"debug"};
	   return 0;
       }
   }
   if ($object->{"debug"}) {
       print "Checkpending position = ".$object->{curpos};
       print " interval = ".$object->interval."\n";
   }
   
   my $endpos=sysseek($object->{handle},0,SEEK_END);
   if ($endpos<$object->{curpos}) { 
       $object->{curpos}=0;
   } elsif (($object->{curpos}==$endpos) 
	       && (time()-$object->{'lastread'})>$object->{'resetafter'}) {
       $object->reset_pointers;
   }

#   my $endpos=sysseek($object->{handle},0,SEEK_END);
#   if ($endpos<$object->{curpos}) { 
#       $object->{curpos}=0;
#   }
   if ($endpos-$object->{curpos}) {
       sysseek($object->{handle},$object->{curpos},SEEK_SET);
   }
   return ($endpos-$object->{curpos});
}

sub read {
    my $object=shift @_;
    my $len;
    my $cnt;
    my $crs=$object->{"buffer"}=~tr/\n//; # Count newlines in buffer 
    print "read - $crs waiting in buffer\n" if $object->{"debug"};
    while (!$crs) {
	print "Reading loop entered\n" if $object->{"debug"};
	$cnt=0;
	while (!($len=$object->checkpending)) {
	    return "" if $object->nowait;
	    sleep($object->interval);               # maybe should be adjusted?
	    if ($cnt++>$object->adjustafter) {
		$cnt=0;
		$object->interval($object->interval*10);
	    }
	}
	sysread($object->{handle},$object->{"buffer"},
		$len,length($object->{"buffer"}));
	$object->{curpos}=sysseek($object->{handle},
				  $object->{curpos}+$len,SEEK_SET);
    
	$crs=$object->{"buffer"}=~tr/\n//;
	if ($object->{"debug"}) {
	    print "Got something ($len). there are now $crs newlines in buffer (";
	    print length($object->{"buffer"})." bytes)\n";
	}

	next unless $crs;
#    $object->{interval}=(time-$object->{lastread})/$crs;
	my $tmp=time; 
	$object->interval(($tmp-($object->{lastread}))/$crs);
	$object->{lastread}=$tmp;
    }
    my $str=substr($object->{"buffer"},0,1+index($object->{"buffer"},"\n"));
    $object->{"buffer"}=substr($object->{"buffer"},
			       1+index($object->{"buffer"},"\n"));
    return $str;
}

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

File::Tail - Perl extension for reading from continously updated files

=head1 SYNOPSIS

  use File::Tail;
  $file=File::Tail->new("/some/log/file");
  while (defined($line=$file->read)) {
      print "$line";
  }

  use File::Tail;
  $file=File::Tail->new(name=>$name, maxinterval=>300, adjustafter=>7);
  while (defined($line=$file->read)) {
      print "$line";
  }

Note that the above script will never exit. If there is nothing being written
to the file, it will simply block.

=head1 DESCRIPTION

The primary purpose of File::Tail is reading and analysing log files while
they are being written, which is especialy usefull if you are monitoring
the logging process with a tool like Tobias Oetiker's MRTG.

The module tries very hard NOT to "busy-wait" on a file that has little 
traffic. Any time it reads new data from the file, it counts the number
of new lines, and divides that number by the time that passed since data
were last written to the file before that. That is considered the average
time before new data will be written. When there is no new data to read, 
C<File::Tail> sleeps for that number of seconds. Thereafter, the waiting 
time is recomputed dynamicaly. Note that C<File::Tail> never sleeps for
more than the number of seconds set by C<maxinterval>.

Note that the sleep and time used are from Time::HiRes, so this module
should do the right thing even if the time to sleep is less than one second.

The logwatch script (also included) demonstrates several ways of calling 
the methods.

=head1 CONSTRUCTOR

=head2 new ([ ARGS ]) 

Creates a C<File::Tail>. If it has only one paramter, it is assumed to 
be the filename. If the open fails, the module performs a croak. I
am currently looking for a way to set $! and return undef. 

You can pass several parameters to new:

=over 4

=item name

This is the name of the file to open. The file will be opened for reading.
This must be a regular file, not a pipe or a terminal (i.e. it must be
seekable).

=item maxinterval

The maximum number of seconds (real number) that will be spent sleeping.
Default is 60, meaning C<File::Tail> will never spend more than sixty
seconds without checking the file.

=item interval

The initial number of seconds (real number) that will be spent sleeping,
before the file is first checked. Default is ten seconds, meaning C<File::Tail>
will sleep for 10 seconds and then determine, how many new lines have appeared 
in the file.

=item adjustafter

The number of C<times> C<File::Tail> waits for the current interval,
before adjusting the interval upwards. The default is 10.

=item resetafter

The number of seconds after last change when C<File::Tail> decides 
the file may have been closed and reopened. The default is 
adjustafter*maxinterval.

=item nowait

Does not block on read, but returns an empty string if there is nothing
to read. DO NOT USE THIS unless you know what you are doing. If you 
are using it in a loop, you probably DON'T know what you are doing.
If you want to read tails from multiple files, use select.

=item debug

Set to nonzero if you want to see more about the inner workings of
File::Tail. Otherwise not useful.

=item errmode

Modeled after the methods from Net:Telnet, here you decide how the
errors should be handled. The parameter can be a code reference which
is called with the error string as a parameter, an array with a code
reference as the first parameter and other parameters to be passed to 
handler subroutine, or one of the words:

return  - ignore any error (just put error message in errmsg).
warn    - output the error message but continue
die     - display error message and exit

Default is die.

=back 

=head1 METHODS

=head2 read

C<read> returns one line from the input file. If there are no lines
ready, it blocks until there are.

=head1 TO BE DONE

The next version will support some form of "select" call, which will
make it possible to read from several File::Tail files at once, as well
as reading from sockets and File::Tail files without polling.

Also planned for 0.8: tail C<-n> functionality, using $/ instead of \n to
separate "lines" (which should make it possible to read wtmp type files).

Tests should be devised and put into test.pl.

=head1 AUTHOR

Matija Grabnar, matija.grabnar@arnes.si

=head1 SEE ALSO

perl(1), tail (1), 
MRTG 

(http://ee-staff.ethz.ch/~oetiker/webtools/mrtg/mrtg.html)

=cut

