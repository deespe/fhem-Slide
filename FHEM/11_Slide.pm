#####################################################################################
# $Id: 11_Slide.pm 18798 2019-03-05 19:13:28Z DeeSPe $
#
# Usage
#
# define <name> Slide <ID>
#
#####################################################################################

package main;

use strict;
use warnings;
use POSIX;
use JSON;
use HttpUtils;

my $version = "0.1.0";

sub Slide_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}        = "^{\"id\":\".*\"";
  $hash->{AttrFn}       = "Slide_Attr";
  $hash->{DefFn}        = "Slide_Define";
  $hash->{GetFn}        = "Slide_Get";
  $hash->{SetFn}        = "Slide_Set";
  $hash->{CopyFn}       = "Slide_Copy";
  $hash->{UndefFn}      = "Slide_Undef";
  $hash->{ParseFn}      = "Slide_Parse";
  $hash->{AttrList}     = "disable:1,0 ".
                          "disabledForIntervals ".
                          "interval ".
                          $readingFnAttributes;
  foreach (sort keys %{$modules{Slide}{defptr}})
  {
    my $hash = $modules{Slide}{defptr}{$_};
    $hash->{VERSION} = $version;
  }
}

sub Slide_Define($$)
{
  my ($hash,$def) = @_;
  my @args = split " ",$def;
  my ($name,$type,$id) = @args;
  return "Usage: define <name> Slide <ID>" if (@args != 3);
  $hash->{DEVICEID}   = $id;
  $hash->{VERSION}    = $version;
  my $iodev = $modules{SlideCloud}{defptr}{BRIDGE}->{NAME};
  if ($init_done && !defined $hash->{OLDDEF})
  {
    $attr{$name}{IODev}       = $iodev;
    $attr{$name}{icon}        = "fts_door_slide_2w";
    $attr{$name}{room}        = "Slide";
  }
  AssignIoPort($hash,$iodev) if (!$hash->{IODev});
  if (defined($hash->{IODev}->{NAME}))
  {
    Log3 $name,3,"Slide ($name) - I/O device is $hash->{IODev}->{NAME}";
  }
  else
  {
    Log3 $name,1,"Slide ($name) - no I/O device";
  }
  $iodev = $hash->{IODev}->{NAME};
  my $d = $modules{Slide}{defptr}{$id};
  return "Slide device $name on SlideCloud $iodev already defined." if (defined($d) && $d->{IODev} == $hash->{IODev} && $d->{NAME} ne $name);
  Log3 $name,3,"Slide ($name) - defined Slide with DEVICEID: $id";
  readingsSingleUpdate($hash,"state","initialized",0);
  $modules{Slide}{defptr}{$id} = $hash;
  return;
}

sub Slide_Undef($$)
{
  my ($hash,$arg) = @_;
  my $id = $hash->{DEVICEID};
  delete $modules{Slide}{defptr}{$id};
  return;
}

sub Slide_Get($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  return if (IsDisabled($name) && $cmd ne "?");
  my $para = "position";
  return "get $name needs one parameter: $para" if (!$cmd);
  if (lc $cmd eq "position")
  {
    return "not implemented yet";
  }
  else
  {
    return $para ? "Unknown argument $cmd for $name, choose one of $para" : undef;
  }
}

sub Slide_Set($@)
{
  my ($hash,$name,@aa) = @_;
  my ($cmd,@args) = @aa;
  my $value = (defined($args[0])) ? $args[0] : undef;
  return if (IsDisabled($name) && $cmd ne "?");
  return "\"set $name $cmd\" needs two arguments at maximum" if (@aa > 2);
  my ($err,$token) = Slide_retriveVal("Slide_".$name."_token");
  Log3 $name,1,"$err - not able to get token" if ($err);
  my @par;
  push @par,"position:slider,0,0.01,1";
  if (lc $cmd eq "position")
  {
    return;
  }
  my $para = join(" ",@par);
  return $para ? "Unknown argument $cmd for $name, choose one of $para" : undef;
}

sub Slide_Attr(@)
{
  my ($cmd,$name,$attr_name,$attr_value) = @_;
  my $hash  = $defs{$name};
  my $err;
  if ($cmd eq "set")
  {
    if ($attr_name eq "disabled")
    {
      $err = "must be 1 to disable or delete the attribute to enable" if ($attr_value !~ /^1$/);
    }
    elsif ($attr_name eq "disabledForIntervals")
    {
    }
  }
  else
  {
    #
  }
  return $err ? $err : undef;
}

1;

=pod
=item device
=item summary    control Slide devices over cloud API
=item summary_DE Steuerung von Slide Ger&auml;ten &uuml;ber Cloud API
=begin html

<a name="Slide"></a>
<h3>Slide</h3>
<ul>
  With <i>Slide</i> you are able to control Slide devices.<br>
  <br>
  <a name="Slide_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Slide &lt;E-MAIL&gt; &lt;PASSWORD&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  Example for running Slide:
  <br><br>
  <ul>
    <code>define slc Slide jondoe@apple.com mYs€cR3t</code><br>
  </ul>
  <br><br>
  If you have homebridgeMapping in your attributes an appropriate mapping will be added, genericDeviceType as well.
  <br>
  <a name="Slide_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>password</i><br>
      set device password
    </li>
  </ul>  
  <br>
  <a name="Slide_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>update</i><br>
      get status update
    </li>
  </ul>
  <br>
  <a name="Slide_attr"></a>
  <p><b>Attributes</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      stop polling and disable device completely<br>
      default: 0
    </li>
  </ul>
  <br>
  <a name="Slide_read"></a>
  <p><b>Readings</b></p>
  <p>All readings updates will create events.</p>
  <ul>
    <li>
      <i>state</i><br>
      current state
    </li>
  </ul>
</ul>

=end html
=begin html_DE

<a name="Slide"></a>
<h3>Slide</h3>
<ul>
  Mit <i>Slide</i> k&ouml;nnen Slide Ger&auml;te gesteuert werden.<br>
  <br>
  <a name="Slide_define"></a>
  <p><b>Define</b></p>
  <ul>
    <code>define &lt;name&gt; Slide &lt;E-MAIL&gt; &lt;PASSWORT&gt; [&lt;INTERVAL&gt;]</code><br>
  </ul>
  <br>
  Beispiel f&uuml;r:
  <br><br>
  <ul>
    <code>define slc Slide jondoe@apple.com mYs€cR3t</code><br>
  </ul>
  <br><br>
  Wenn homebridgeMapping in der Attributliste ist, so wird ein entsprechendes Mapping hinzugef&uuml;gt, ebenso genericDeviceType.
  <br>
  <a name="Slide_set"></a>
  <p><b>Set</b></p>
  <ul>
    <li>
      <i>password</i><br>
      Passwort des Ger&auml;tes setzen
    </li>
  </ul>  
  <br>
  <a name="Slide_get"></a>
  <p><b>Get</b></p>
  <ul>
    <li>
      <i>update</i><br>
      Status Update abrufen
    </li>
  </ul>
  <br>
  <a name="Slide_attr"></a>
  <p><b>Attribute</b></p>
  <ul>
    <li>
      <i>disable</i><br>
      Anhalten der automatischen Abfrage und komplett deaktivieren<br>
      Voreinstellung: 0
    </li>
  </ul>
  <br>
  <a name="Slide_read"></a>
  <p><b>Readings</b></p>
  <p>Alle Aktualisierungen der Readings erzeugen Events.</p>
  <ul>
    <li>
      <i>state</i><br>
      aktueller Zustand
    </li>
  </ul>
</ul>

=end html_DE
=cut
