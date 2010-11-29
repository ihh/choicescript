#!/usr/bin/perl -W

use Getopt::Long;
use Graph::Easy;
use Graph::Easy::Parser::Graphviz;
use Pod::Usage;

# template label prefixes & suffixes
my %suffix = map (($_=>".$_"), qw(top bottom prompt choose text auto show allow txt));
my $global_prefix = 'story';

# keywords that extend ChoiceScript (sort of)
my $template_keyword = "*template";
my $include_keyword = "*include";

# regexes
my $name_regex = '[A-Za-z_\.][A-Za-z_\.\d]*';
my $notname_char_regex = '[^A-Za-z_\.\d]';
my $template_keyword_regex = quotemeta $template_keyword;
my $include_keyword_regex = quotemeta $include_keyword;

# Graph::Easy node & edge attributes
my $edge_label_attr = "label";  # edge attribute
my $node_label_attr = "label";  # node attribute
my $edge_sort_attr = "minlen";  # we use the 'minlen' attribute to sort edges; 'weight' would be preferable, but Graph::Easy ignores this for some reason

# command-line options
my $man = 0;
my $help = 0;
my $start_node;
my $end_node;
my $use_finish = 0;
my $create_scene_files = 0;
my $track_node_visits = 0;
my @template_filename;
my $keep_template_stubs = 0;

# parse command-line
GetOptions ('help|?' => \$help,
	    'man' => \$man,
	    'initial=s' => \$start_node,
	    'final=s' => \$end_node,
	    'finish' => \$use_finish,
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
my @orig_node = @node;   # keep track of original node list (we may add a dummy end node later)

my @trans;
my %sources = map (($_ => []), @node);
for my $edge ($graph->edges()) {
    my ($from, $to, $attr) = ($edge->from()->name(), $edge->to()->name(), $edge->get_attributes());
    push @trans, [$from, $to, $attr];
    push @{$sources{$to}}, $from;
    if ($graph->is_undirected) {
	push @trans, [$to, $from, $attr];
	push @{$sources{$from}}, $to;
    }
}

# sort transitions by source
# $choice{$source} = [[$dest1,$attrs1],[$dest2,$attrs2],...]
my %choice;
grep (push(@{$choice{$_->[0]}}, [@$_[1,2]]), @trans);

# ensure we have a start node
unless (defined($start_node) && grep ($_ eq $start_node, @node)) {
    # look for nodes with nothing incoming
    my @src_only = grep (@{$sources{$_}}==0, @node);
    if (@src_only == 1) {
	$start_node = $src_only[0];
    } else {
	$start_node = undef;
    }
}

# ensure the start node is the first in @node, and therefore, the first in the scene
if (defined $start_node) {
    @node = ($start_node, grep ($_ ne $start_node, @node));
}

# ensure we have an end node
unless ($use_finish) {
    unless (defined($end_node) && grep ($_ eq $end_node, @node)) {
	# look for nodes with nothing outgoing
	my @dest_only = grep (!exists $choice{$_}, @node);
	if (@dest_only == 1) {
	    $end_node = $dest_only[0];
	} else {
	    # create a unique name
	    my $finish_count = 1;
	    do {
		$end_node = "finish" . ($finish_count > 1 ? $finish_count : "");
	    } while (exists $choice{$end_node});
	}
    }

    # ensure the end node is the last in @node, and therefore, the last in the scene
    if (defined $end_node) {
	@node = (grep ($_ ne $end_node, @node), $end_node);
    }
}

# get all edge labels & the set of nodes that each such edge label points to
my %edge_label_dests;
for my $src_dest_attr (@trans) {
    my $preview = getAttr ($src_dest_attr->[2], $edge_label_attr, undef);
    push @{$edge_label_dests{$preview}}, $src_dest_attr->[1] if defined $preview;
}

# distinguish "segue" nodes (nodes whose predecessors all have only one outgoing transition, and so are not reached by a choice of the player) from "choice" nodes (nodes reached by a "choice" edge)
# the need for this is a bit hacky: it's because our default edge text, "You choose X.", only depends on the destination node (X), and not on the source.
# if the edge has a non-default label (i.e. not "choose_X"), then we don't count that edge as a "choice" edge for the purposes of this test.
my @segue_node;
my @choice_node;
for my $dest (@node) {
    my $is_choice = 0;
    for my $src (@{$sources{$dest}}) {  # there exists an edge src->dest
	if (@{$choice{$src}} > 1) {  # there is more than one outgoing edge from src
	    for my $dest_attrs (@{$choice{$src}}) {
		if ($dest_attrs->[0] eq $dest) {
		    if (!defined (getAttr ($dest_attrs->[1], "label"))) {   # there is at least one src->dest edge using the default label
			$is_choice = 1;  # if these conditions are met, dest is a "choice node"
		    }
		}
	    }
	}
    }
    if ($is_choice) {
	push @choice_node, $dest;
    } else {
	push @segue_node, $dest;
    }
}

# initialize default templates
my %template = $keep_template_stubs
    ? ()
    : (map (($global_prefix.$suffix{$_} => []), qw(top bottom)),
       defined($end_node) ? ($end_node.$suffix{'text'} => []) : (),
       map (($_.$suffix{'prompt'} => [$_]), @node),
       map (($_.$suffix{'prompt'} => [$_]), keys %edge_label_dests),
       map (($_.$suffix{'choose'} => ["You choose " . $_ . ".", "*page_break"]), @choice_node),
       map (($_.$suffix{'choose'} => ["*page_break"]), @segue_node),
       map (($_.$suffix{'choose'} => [$_]), keys %edge_label_dests),
       map (($_.$suffix{'text'} => ["Currently: " . $_ . ($track_node_visits ? " (visit #\${visits}, turn #\${turns}, previously \${previous_node\})." : ".")]),
	    @orig_node));

# load templates
for my $template_filename (@template_filename) {
    local *TMPL;
    local $_;
    if (-d $template_filename) {
	local *DIR;
	opendir DIR, $template_filename or die "Couldn't open template directory '$template_filename': $!";
	my @text_filename = grep (/^[^\.]/ && (-T "$template_filename/$_"), readdir (DIR));
	closedir DIR;
	for my $filename (@text_filename) {
	    open TMPL, "<$template_filename/$filename" or die "Couldn't open template file '$template_filename/$filename': $!";
	    my @tmpl = <TMPL>;
	    close TMPL;
	    grep (chomp, @tmpl);
	    $template{$filename} = \@tmpl;
	}
    } else {
	open TMPL, "<$template_filename" or die "Couldn't open template file '$template_filename': $!";
	my $current_template;
	while (<TMPL>) {
	    if (/^\s*$template_keyword_regex\s+($name_regex)\s*$/) {
		$current_template = $1;
		$template{$current_template} = [];
	    } elsif (defined $current_template) {
		chomp;
		push @{$template{$current_template}}, $_;
	    }
	}
	close TMPL;
    }
}
# trim off empty lines at the end of templates
while (my ($tmpl, $val) = each %template) {
    while (@$val && $val->[$#$val] !~ /\S/) {
	pop @$val;
    }
}

# identify ".auto" nodes and automatically create default .allow templates if none exist
my @auto_nodes = grep (exists($template{$_.$suffix{'auto'}}), @node);
unless ($keep_template_stubs) {
    for my $node (@auto_nodes) {
	for my $dest_attrs (@{$choice{$node}}) {
	    my ($dest, $attrs) = @$dest_attrs;
	    my $choose = getAttr ($attrs, $edge_label_attr, $dest) . $suffix{'allow'};
	    $template{$can_choose} = ["1=1"] unless exists $template{$can_choose};
	}
    }
}

# create template regex
my $template_regex = join('|',map(quotemeta(),keys(%template)));

# variables
my %var;
if ($track_node_visits) {
    %var = (%var,
	    map (($_ => '"nowhere"'),
		 qw(node previous_node)),
	    map (($_ => 0),
		 qw(visits turns),
		 map ($_."_visits", @node)));
}

# startup code
my @startup = ($global_prefix.$suffix{'top'});
# create variables
my @vars = sort keys %var;
my $create = $create_scene_files ? "*create" : "*temp";
push @startup, map ("$create $_", @vars);
push @startup, map (defined($var{$_}) ? "*set $_ $var{$_}" : (), @vars);

# finish code
my $finish = defined($end_node) && !$use_finish ? "*goto $end_node" : "*finish";

# loop over sources
for my $node_pos (0..$#node) {
    my $node = $node[$node_pos];
    my @out;
    push @out, indent (0,
		       $node_pos == 0 ? @startup : (),
		       "",
		       "*comment $node",
		       $create_scene_files ? undef : "*label $node",
		       $track_node_visits ? ("*set turns +1",
					     "*set ${node}_visits +1",
					     "*set visits ${node}_visits",
					     '*set previous_node node',
					     "*set node \"$node\""): (),
		       getAttr ($node_attr{$node}, $node_label_attr, $node) . $suffix{'text'},
		       $node_pos == $#node ? $global_prefix.$suffix{'bottom'} : ());
    my $goto = $create_scene_files ? "*goto_scene" : "*goto";
    if (defined $choice{$node} && @{$choice{$node}} > 1) {
	my $is_auto = exists $template{$node.$suffix{'auto'}};
	push @out, "*choice" if !$is_auto;
	my @choices = sort { getAttr($a->[1],$edge_sort_attr,0) <=> getAttr($b->[1],$edge_sort_attr,0) } @{$choice{$node}};
	for (my $n_choice = 0; $n_choice < @choices; ++$n_choice) {
	    my ($dest, $attrs) = @{$choices[$n_choice]};
	    my $prefix = getAttr ($attrs, $edge_label_attr, $dest);
	    my ($preview, $choose, $can_preview, $can_choose) = map ($prefix . $suffix{$_}, qw(prompt choose show allow));
	    my $conditional_preview = (exists($template{$can_choose}) ? "*selectable_if ( $can_choose ) " : "") . "# $preview";
	    push @out, indent ($is_auto ? 0 : 2,
			       $is_auto ? () : "*comment $node -> $dest",  # suppress comments in *if...*elseif...*else blocks, as they make ChoiceScript choke. Messy
			       $is_auto
			       ? ($n_choice==0 ? "*if $can_choose" : "*elseif $can_choose")
			       : (exists($template{$can_preview})
				  ? ("*if $can_preview", indent(1,$conditional_preview))
				  : $conditional_preview),
			       indent (2,
				       $choose,
				       "$goto $dest"),
			       "");
	}
	push @out, $is_auto ? ("*else", indent(2,$finish)) : "";
    } elsif (defined $choice{$node} && @{$choice{$node}} == 1) {
	my ($dest, $attrs) = @{$choice{$node}->[0]};
	my $choose = getAttr ($attrs, $edge_label_attr, $dest) . $suffix{'choose'};
	push @out, indent (0,
			   "",
			   "*comment $node -> $dest",
			   $choose,
			   "$goto $dest",
			   "");
    } elsif ($node_pos != $#node) {
	push @out, $finish, "";
    }

    # substitute templates
    my @subst = substitute_templates (@out);

    # write output
    if ($create_scene_files) {
	my $scene_filename = $node . $suffix{'txt'};
	local *SCENE;
	open SCENE, ">$scene_filename" or die "Couldn't open $scene_filename: $!";
	print SCENE map ("$_\n", @subst);
	close SCENE or die "Couldn't close $scene_filename: $!";
    } else {
	print map ("$_\n", @subst);
   }
}

# write a placeholder *goto_scene if we're creating scene files
print "*goto_scene $node[0]\n" if $create_scene_files && @node;

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
	if ($line =~ /^(\s*.*)\b($template_regex)(|$notname_char_regex.*)$/) {
	    my ($prelude, $tmpl, $rest) = ($1, $2, $3);
	    if (defined $template{$tmpl}) {
		my @tmpl = @{$template{$tmpl}};
		unshift @lines, map ("$prelude$_$rest", @tmpl);
	    } else {
		push @subst, $line;
	    }
	} elsif ($line =~ /^(\s*.*)$include_keyword_regex\s+(\S+)(.*)/) {
	    my ($prelude, $filename, $rest) = ($1, $2, $3);
	    local *INCL;
	    open INCL, "<$filename" or die "Couldn't open included filename $filename: $1";
	    my @tmpl = <INCL>;
	    close INCL;
	    grep (chomp, @tmpl);
	    unshift @lines, map ("$prelude$_$rest", @tmpl);
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
    -initial <name>   specify initial node
    -final <name>     specify final node
    -finish           use *finish to exit scene
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

=item B<-initial> name

Specify the name of the initial node in the graph (i.e. where the choicescript scene begins).

This node will appear first in the generated choicescript, leading to the intuitive behavior if the generated file is included by another file.

If no value is specified, the program will look for a node with no incoming transitions.

=item B<-final> name

Specify the name of the final node in the graph.
Instead of exiting the scene with *finish, the game will *goto this node.

This node will appear last in the generated choicescript, leading to the intuitive behavior if the generated file is included by another file.

If no value is specified, the program will look for a unique node with no outgoing transitions.
If such a node is not found (or is not unique), the program will attempt to create a unique name.

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
You can use the option multiple times to load multiple template definition files.

The format of each template definition file is as follows:

 *template label1.text
 ChoiceScript goes here
 More ChoiceScript goes here

 *template label2.text
 *if some_condition
   Something indented can go here
 Back to the original indent

 *template label3.choose
 You make your choice.
 ...

This will substitute all instances of 'label1', 'label2' and 'label3' with the corresponding stanzas, using the appropriate indenting.

Alternatively, instead of a template definitions file, a template directory will be used.
In this case, rather than reading the definitions from one monolithic file,
the program will look for text files in the template directory whose filenames are the template labels
("label1.text", "label2.text", "label3.choose" in the above example).

The following templates are created/checked automatically:

  NODE.prompt    text displayed when NODE appears in a list of choice options (NODE = graphviz node label)
  NODE.choose    text displayed when NODE is selected, or is the only possible choice
  NODE.text      text displayed when NODE is visited
  NODE.auto      dummy template; if defined, NODE will use "*if NODE.allow -> NODE.choose" instead of "*choice -> #NODE.prompt -> NODE.choose"
  NODE.show      if defined, a ChoiceScript expression that must evaluate true for NODE to be visible in a list of choices
  NODE.allow     if defined, a ChoiceScript expression that must evaluate true for NODE to be selectable (vs grayed-out)

  story.top      occurs once at the very beginning of the file
  story.bottom   occurs once at the very end of the file

  *include FILE  pastes in the contents of FILE

The NODE in the edge-related templates ('NODE.prompt', 'NODE.choose', 'NODE.show' and 'NODE.allow')
can be overridden by specifying the 'label' edge attribute in the graphviz file.

=item B<-stubs>

Do not define the default templates (.top, NODE.prompt, NODE.choose, NODE.text).
Instead leave them as stubs visible to the play-tester.

=back

=head1 DESCRIPTION

B<graph2choice> will read a graph file in GraphViz DOT format and generate minimal stubs for a ChoiceScript scene.

In the GraphViz file, use 'label' node/edge attributes for narrative text, and 'tooltip' edge attribute for choice text.

Use the 'minlen' edge attribute to control the ordering of choices.
Edges with a higher 'minlen' attribute will appear further down the list.

Undirected graphs are implicitly converted to directed graphs with edges in both directions (useful for creating maps).

=cut
