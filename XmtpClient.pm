package Net::XmtpClient;

=head1 NAME

Net::XmtpClient - Implement SMTP/LMTP client skeleton

=head1 SYNOPSIS

  use Net::XmtpClient;

  my $Client = Net::XmtpClient->new(Server => $Server, Port => $Port);
  my $Socket = $Client->{Socket};

  my ($Code, $Rem, $Other);
  ($Code, $Rem, $Other) = $Client->banner();
  ($Code, $Rem, $Other) = $Client->helo('host');
  ($Code, $Rem, $Other) = $Client->mail_from('addr@domain.com');
  ($Code, $Rem, $Other) = $Client->rcpt_to('other@domain.com');
  ($Code, $Rem, $Other) = $Client->data();

  while (<>) {
    chomp;
    print $Socket $_, "\r\n";
  }

  ($Code, $Rem, $Other) = $Client->end_data_smtp();

  my @Responses = $Client->end_data_lmtp();
  

=head1 DESCRIPTION

This module implements a SMTP/LMTP client. You connect to
a server, and send the various SMTP/LMTP commands by
calling the appropriate methods.

=head1 RETURN VALUES

Each method call returns the same basic response, a
3 element array with:

=over 4

=item Code

The SMTP/LMTP response code

=item Rem

The remainder of the final response line

=item Other

An array ref with any other response lines that
were returned before the final response line

=back

=cut

# Use modules/constants {{{
use IO::Socket::INET;
use IO::Socket::UNIX;

# Avoid UTF-8 regexp issues. Treat everything as pure
#  binary data
no utf8;
use bytes;

# Standard use items
use Data::Dumper;
use strict;
# }}}

sub new {
  my $Proto = shift;
  my $Class = ref($Proto) || $Proto;
  my %Args = @_;

  $Args{Server} || die "No 'Server' specified";

  # Set ourself to empty to start with
  my $Self = {};
  bless ($Self, $Class);

  my $Server = $Self->{Server} = $Args{Server};
  my $Port = $Self->{Port} = $Args{Port} || 25;
  my $Debug = $Self->{Debug} = $Args{Debug} || 0;
  my $Logger = $Self->{Logger} = $Args{Logger} || 0;

  $Self->{LastSent} = '';
  $Self->{LastResp} = '';
  $Self->{RespCode} = '';

  $Self->debug("Connecting to '$Server' on '$Port'");

  my $Socket;
  if ($Server =~ m{^/}) {
    $Socket = IO::Socket::UNIX->new(
      Peer => $Server,
      Timeout => 120,
      Type => SOCK_STREAM
    ) || return undef;
  } else {
    $Socket = IO::Socket::INET->new(
      PeerAddr => $Server,
      PeerPort => $Port,
      Timeout => 120,
      Proto => 'tcp',
      Type => SOCK_STREAM
    ) || return undef;
  }

  # Force flushing after every write to the socket
  my $ofh = select($Socket); $| = 1; select ($ofh);

  $Self->{Socket} = $Socket;

  # Read server banner response
  $Self->read_server_response();

  return $Self;
}

sub debug {
  my ($Self, $Msg) = @_;
  if ($Self->{Debug}) {
    $Msg = "$Msg. Last sent=$Self->{LastSent}, code=$Self->{RespCode}, response=$Self->{LastResp}\n";
    if ( $Self->{Logger} ) {
      $Self->{Logger}->mylog($Msg);
    } else {
      warn $Msg;
    }
  }
}

=item I<read_server_response($Self)

Get the response code and message from the server
for the last sent command. Returns the response
code.

=cut
sub read_server_response {
  my $Self = shift;

  my $Socket = $Self->{Socket};

  my @RespLines;

  # Get response line (repeat if continued response)
  my $Resp = <$Socket> || '';
  $Resp =~ s/\r\n$//;
  while ($Resp =~ /^\d{3}-(.*)$/) {
    push @RespLines, $1;
    $Resp = <$Socket> || '';
    $Resp =~ s/\r\n$//;
  }
  my ($Code) = $Resp =~ /^(\d{3})\s+(.*)$/;
  push @RespLines, $2;

  $Self->{RespCode} = $Code || '';
  $Self->{LastResp} = $2 || '';
  $Self->{RespLines} = \@RespLines;

  $Self->debug("Completed command");

  return $Code;
}

sub last_response {
  my $Self = shift;
  return ($Self->{RespCode} || '', $Self->{LastResp} || '');
}

sub full_response {
  my $Self = shift;
  return ($Self->{RespCode} || '', @{$Self->{RespLines} || []});
}

sub no_socket {
  my $Self = shift;

  my $Resp = "No connection to server";
  $Self->{RespLines} = [ $Resp ];
  $Self->{RespCode} = '421';
  $Self->{LastResp} = $Resp;
}

sub send_to_client {
  my $Self = shift;
  my $Socket = $Self->{Socket};
  $Self->{LastSent} = $_[0];
  print $Socket shift(@_);
}

sub helo {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("HELO " . join(' ', @_) . "\r\n");
  return $Self->read_server_response();
}

sub ehlo {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("EHLO " . join(' ', @_) . "\r\n");
  return $Self->read_server_response();
}

sub lhlo {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("LHLO " . join(' ', @_) . "\r\n");
  return $Self->read_server_response();
}

sub noop {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("NOOP\r\n");
  return $Self->read_server_response();
}

sub mail_from {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("MAIL FROM:" . join(' ', "<" . shift(@_) . ">", @_) . "\r\n");
  return $Self->read_server_response();
}

sub rcpt_to {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("RCPT TO:" . join(' ', "<" . shift(@_) . ">", @_) . "\r\n");
  return $Self->read_server_response();
}

sub data {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("DATA\r\n");
  return $Self->read_server_response();
}

sub rset {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("RSET\r\n");
  return $Self->read_server_response();
}

sub quit {
  my $Self = shift;

  return $Self->no_socket() unless $Self->{Socket};
  $Self->send_to_client("QUIT\r\n");
  my $Res = $Self->read_server_response();
  close($Self->{Socket});
  $Self->{Socket} = undef;
  return $Res;
}

1;

