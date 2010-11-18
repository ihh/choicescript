#!/usr/bin/perl -W

use Getopt::Long;
use Graph::Easy;
use Graph::Easy::Parser::Graphviz;
use Pod::Usage;

# regexes
my $name_regex = '[A-Za-z_][A-Za-z_\d]*';

# Graph::Easy node & edge attributes
my $preview_attr = "title";  # edge attribute; graphviz 'tooltip' gets converted to Graph::Easy 'title'
my $choose_attr = "label";  # edge attribute
my $view_attr = "label";  # node attribute
my $edge_sort_attr = "minlen";  # we use the 'minlen' attribute to sort edges; 'weight' would be preferable, but Graph::Easy ignores this for some reason

# command-line options
my $man = 0;
my $help = 0;
my $start_node = "start";
my $create_scene_files = 0;
my $track_node_visits = 0;
my @template_filename;
my $keep_template_stubs = 0;

# parse command-line
GetOptions ('help|?' => \$help,
	    'man' => \$man,
	    'init=s' => \$start_node,
	    'scenes' => \$create_scene_files,
	    'track' => \$track_node_visits,
	    'template=s' => \@template_filename,
	    'stubs' => \$keep_template_stubs) or pod2usage(2);
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# read DOT file into Graph::Easy object
my $parser = Graph::Easy::Parser::Graphviz->new();
if (@ARGV != 1) { warn "Please specify a filename!\n"; pod2usage(2) }
my ($dotfile) = @ARGV;
my $graph = $parser->from_file($dotfile);

# extract nodes & edges
my %node_attr;
for my $node ($graph->nodes()) {
    $node_attr{$node->name()} = $node->get_attributes();
}

my @node = keys %node_attr;

my @trans;
my %edges_to;
for my $edge ($graph->edges()) {
    my ($from, $to, $attr) = ($edge->from()->name(), $edge->to()->name(), $edge->get_attributes());
    push @trans, [$from, $to, $attr];
    ++$edges_to{$to};
    if ($graph->is_undirected) {
	push @trans, [$to, $from, $attr];
	++$edges_to{$from};
    }
}

# ensure we have a start node
unless (grep ($_ eq $start_node, @node)) {
    # look for nodes with nothing incoming
    my @src_only = grep (!defined($edges_to{$_}), @node);
    if (@src_only == 1) {
	$start_node = $src_only[0];
    } else {
	warn
	    "Warning: initial node '$start_node' not found.\n",
	    "Node sequence will be random... better add a *goto\n";
    }
}

# ensure the start node is the first in @node, and therefore, the first in the scene
# (beyond this, the ordering of nodes in the choicescript file doesn't matter too much)
if (grep ($_ eq $start_node, @node)) {
    @node = ($start_node, grep ($_ ne $start_node, @node));
}

# sort transitions by source
my %choice;
grep (push(@{$choice{$_->[0]}}, [@$_[1,2]]), @trans);

# get all preview labels
my %preview_destination;
for my $src_dest_attr (@trans) {
    my $preview = getAttr ($src_dest_attr->[2], $preview_attr, undef);
    $preview_destination{$preview} = $src_dest_attr->[1] if defined $preview;
}

# get choice nodes & segue nodes
my @choice_node = grep (exists($choice{$_}) && @{$choice{$_}} >= 2, @node);
my @segue_node = grep (exists($choice{$_}) && @{$choice{$_}} == 1, @node);

# initialize default templates
my %template = $keep_template_stubs
    ? ()
    : ('top_of_file' => [],
       map (("preview_$_" => [$_]), @node),
       map (($_ => [$preview_destination{$_}]), keys %preview_destination),
       map (("choose_$_" => ["You choose " . $_ . ".", "*page_break"]), @choice_node),
       map (("choose_$_" => ["*line_break", "Next: " . $_ . ".", "*page_break"]), @segue_node),
       map (("view_$_" => ["Currently: " . $_ . ($track_node_visits ? " (visit #\${visits})." : ".")]), @node));

# load templates
for my $template_filename (@template_filename) {
    local *TMPL;
    local $_;
    open TMPL, "<$template_filename" or die "Couldn't open template file '$template_filename': $!";
    my $current_template;
    while (<TMPL>) {
	if (/^\s*\*template\s+($name_regex)\s*$/) {
	    $current_template = $1;
	    $template{$current_template} = [];
	} elsif (defined $current_template) {
	    chomp;
	    push @{$template{$current_template}}, $_;
	}
    }
    close TMPL;
}
# trim off empty lines at the end of templates
while (my ($tmpl, $val) = each %template) {
    while (@$val && $val->[$#$val] !~ /\S/) {
	pop @$val;
    }
}

# identify "if" nodes and automatically create default can_choose_ templates if none exist
my @if_nodes = grep (exists($template{"if_$_"}), @node);
unless ($keep_template_stubs) {
    for my $node (@if_nodes) {
	for my $dest_attrs (@{$choice{$node}}) {
	    my ($dest, $attrs) = @$dest_attrs;
	    my $choose = getAttr ($attrs, $choose_attr, "choose_$dest");
	    my $can_choose = $choose =~ /^$name_regex$/ ? "can_$choose" : "can_choose_$dest";
	    $template{$can_choose} = ["1=1"] unless exists $template{$can_choose};
	}
    }
}

# create template regex
my $template_regex = '\b(' . join('|',keys(%template)) . '|include_' . $name_regex . ')\b';

# variables
my %var;
if ($track_node_visits) {
    %var = (%var,
	    map (($_ => ""),
		 qw(node previous_node)),
	    map (($_ => 0),
		 qw(visits turns),
		 map ($_."_visits", @node)));
}

# startup code
my @startup = qw(top_of_file);
# create variables
my @vars = sort keys %var;
my $create = $create_scene_files ? "*create" : "*temp";
push @startup, map ("$create $_", @vars);
push @startup, map (defined($var{$_}) ? "*set $_ $var{$_}" : (), @vars);

# loop over sources
for my $node (@node) {
    my @out;
    push @out, indent (0,
		       $node eq $start_node ? @startup : (),
		       "",
		       "*comment $node;",
		       $create_scene_files ? undef : "*label $node",
		       $track_node_visits ? ("*set turns +1",
					     "*set ${node}_visits +1",
					     "*set visits ${node}_visits",
					     'set previous_node ${node}',
					     "set node $node"): (),
		       getAttr ($node_attr{$node}, $view_attr, "view_$node"));
    my $goto = $create_scene_files ? "*goto_scene" : "*goto";
    if (defined $choice{$node} && @{$choice{$node}} > 1) {
	my $is_if = exists $template{"if_$node"};
	push @out, "*choice" if !$is_if;
	my @choices = sort { getAttr($a->[1],$edge_sort_attr,0) <=> getAttr($b->[1],$edge_sort_attr,0) } @{$choice{$node}};
	for (my $n_choice = 0; $n_choice < @choices; ++$n_choice) {
	    my ($dest, $attrs) = @{$choices[$n_choice]};
	    my $preview = getAttr ($attrs, $preview_attr, "preview_$dest");
	    my $choose = getAttr ($attrs, $choose_attr, "choose_$dest");
	    my $can_preview = $preview =~ /^$name_regex$/ ? "can_$preview" : "can_preview_$dest";
	    my $can_choose = $choose =~ /^$name_regex$/ ? "can_$choose" : "can_choose_$dest";
	    my $conditional_preview = (exists($template{$can_choose}) ? "*selectable_if ( $can_choose ) " : "") . "# $preview";
	    push @out, indent ($is_if ? 0 : 2,
			       $is_if ? () : "*comment $node -> $dest;",  # suppress comments in *if...*elseif...*else blocks. Messy
			       $is_if
			       ? ($n_choice==0 ? "*if $can_choose" : "*elseif $can_choose")
			       : (exists($template{$can_preview})
				  ? ("*if $can_preview", indent(1,$conditional_preview))
				  : $conditional_preview),
			       indent (2,
				       $choose,
				       "$goto $dest"),
			       "");
	}
	push @out, $is_if ? ("*else", indent(2,"*finish")) : "";
    } elsif (defined $choice{$node} && @{$choice{$node}} == 1) {
	my ($dest, $attrs) = @{$choice{$node}->[0]};
	my $preview = getAttr ($attrs, $preview_attr, undef);
	my $choose = getAttr ($attrs, $choose_attr, "choose_$dest");
	push @out, indent (0,
			   "",
			   "*comment $node -> $dest;",
			   $preview,
			   $choose,
			   "$goto $dest",
			   "");
    } else {
	push @out, "*finish", "";
    }

    # substitute templates
    my @subst = substitute_templates (@out);

    # write output
    if ($create_scene_files) {
	local *SCENE;
	open SCENE, ">$node.txt" or die "Couldn't create $node.txt: $!";
	print SCENE map ("$_\n", @subst);
	close SCENE or die "Couldn't write $node.txt: $!";
    } else {
	print map ("$_\n", @subst);
   }
}

# and that's it
exit;

# subroutine to extract attribute values & unescape newlines
sub getAttr {
    my ($attrHashRef, $attr, $default) = @_;
    my $val;
    $val = $attrHashRef->{$attr} if exists($attrHashRef->{$attr});
    $val = $default unless defined($val) && length($val) > 0;
    return $val;
}

# subroutine to indent
sub indent {
    my ($indent, @lines) = @_;
    $indent = " " x $indent unless $indent =~ / /;
    return map (defined() ? "$indent$_" : (), @lines);
}

# subroutine to substitute templates
sub substitute_templates {
    my @lines = @_;
    my @subst;
    while (@lines) {
	my $line = shift @lines;
	if ($line =~ /^(\s*.*)$template_regex(.*)$/) {
	    my ($prelude, $tmpl, $rest) = ($1, $2, $3);
	    my @subst;
	    if ($tmpl =~ /^include_(\S+)/) {
		my $filename = $1 . ".txt";
		local *INCL;
		open INCL, "<$filename" or die "Couldn't open included filename $filename: $1";
		@subst = <INCL>;
		close INCL;
	    } else {
		@subst = @{$template{$tmpl}};
	    }
	    unshift @lines, map ("$prelude$_$rest", @subst);
	} else {
	    push @subst, $line;
	}
    }
    return @subst;
}

__END__

=head1 NAME

graph2choice.pl - convert GraphViz files to ChoiceScript

=head1 SYNOPSIS

graph2choice.pl [options] <graph file>

  Options:
    -help,-?          brief help message
    -man              full documentation
    -init <name>      specify initial node
    -scenes           create scene files
    -track            track node visits
    -template <file>  use template defs file
    -stubs            preserve template stubs

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-init> name

Specify the name of the initial node in the graph (i.e. where the choicescript scene begins).

If no value is specified, the program will look for a node named 'start'.

=item B<-scenes>

Create multiple scene files, connected by *goto_scene.

This option overrides the default behavior, which is to print one monolithic stream of choicescript to standard output, containing multiple *label's connected by *goto.

=item B<-track>

Track the number of visits to each node X in a ChoiceScript variable ${X_visits}.

The first time the player visits the node, this variable will be 1; on the next visit, 2; and so on.

For convenience, some other ChoiceScript variables are also set:

 ${visits}         equal to ${X_visits} where X is the node name
 ${turns}          number of turns that the player has been playing
 ${node}           name of the current node (X, in the above example)
 ${previous_node}  name of the previously-visited node

=item B<-template> filename

Substitute templates from a definitions file.

The format of the file is as follows:

 *template label1
 ChoiceScript goes here
 More ChoiceScript goes here

 *template label2
 *if some_condition
   Something indented can go here
 Back to the original indent

 *template label3
 ...

This will substitute all instances of 'label1', 'label2' and 'label3' with the corresponding stanzas, using the appropriate indenting.

The following templates are created/checked automatically:

  top_of_file       occurs once at the very beginning of the file
  preview_NODE      text displayed when NODE appears in a list of choices
  choose_NODE       text displayed when NODE is selected, or is the only possible choice
  view_NODE         text displayed when NODE is visited
  if_NODE           dummy template; if defined, NODE will use "*if can_choose_NODE" instead of "*choice -> #preview_NODE -> choose_NODE"
  can_preview_NODE  if defined, a ChoiceScript expression that must evaluate true for NODE to appear in a list of choices
  can_choose_NODE   if defined, a ChoiceScript expression that must evaluate true for NODE to be selectable (vs grayed-out)
  include_FILE      pastes in the contents of "FILE.txt"

The names 'preview_NODE' and 'choose_NODE' can be overridden by specifying (respectively) the 'tooltip' and 'label' edge attributes in the graphviz file.

Note that if the 'choose_NODE' template name is overridden (by specifying the 'label' edge attribute in the graphviz file), e.g. to XXX, then can_choose_NODE will become can_XXX.
This only works if 'choose_NODE' is overridden to a string that is a valid template name (i.e. no whitespace, punctuation, etc); if not, the default value of 'can_choose_NODE' is kept.

Similarly, if the 'preview_NODE' template name is overridden (by specifying the 'tooltip' edge attribute in the graphviz file), e.g. to YYY, then can_preview_NODE will become can_YYY.
This only works if 'preview_NODE' is overridden to a string that is a valid template name (i.e. no whitespace, punctuation, etc); if not, the default value of 'can_preview_NODE' is kept.

You can use this option multiple times to load multiple template definition files.

=item B<-stubs>

Do not define the default templates (top_of_file, preview_NODE, choose_NODE, view_NODE).
Instead leave them as stubs visible to the player.

=back

=head1 DESCRIPTION

B<graph2choice> will read a graph file in GraphViz DOT format and generate minimal stubs for a ChoiceScript scene.

In the GraphViz file, use 'label' node/edge attributes for narrative text, and 'tooltip' edge attribute for choice text.

Use the 'minlen' edge attribute to control the ordering of choices.
Edges with a higher 'minlen' attribute will appear further down the list.

Undirected graphs are implicitly converted to directed graphs with edges in both directions (useful for creating maps).

=cut
