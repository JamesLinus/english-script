#!/usr/bin/env ruby
# encoding: utf-8
Encoding.default_external="UTF-8"

# begin
require_relative 'interpreter'
require_relative 'interpretation'
require_relative 'tree-builder'
require_relative 'core-functions'
require_relative 'english-tokens'
require_relative 'power-parser'
require_relative 'extensions'
require_relative 'events'

require_relative 'grammar/ruby_grammar'
require_relative 'grammar/loops_grammar'

require_relative 'bindings/shell/betty'
require_relative 'bindings/native/native-scripting'
# rescue
#   puts "Needs ruby 2.x"
#   puts "Trying mruby or rubinius fallback ..."
# end
# require_relative 'bindings/common-scripting-objects'

require 'wordnet'
begin
  require 'linguistics'
#require 'wordnet-defaultdb'
  Linguistics.use(:en, :monkeypatch => true)
rescue Exception => e
  puts "linguistics component needs ruby 2.x, ignoring"
end
#http://99designs.com/tech-blog/ More magic

# look at java AST http://groovy.codehaus.org/Compile-time+Metaprogramming+-+AST+Transformations
# JRuby+Truffle can achieve peak performance well beyond that possible in JRuby at the same time as being a significantly simpler system.
# StaticScope represents lexical scoping of variables and module/class constants.
class EnglishParser < Parser
  include TreeBuilder
  include Interpreter
  include CoreFunctions
  include EnglishParserTokens # module
  include LoopsGrammar # while, as long as, ...
  include RubyGrammar # def, ...
  include Betty # convert a.wav to mp3
  include ExternalLibraries

  attr_accessor :methods, :result, :last_result, :interpretation, :variables, :variableValues,
                :variableType #remove the later!

  def initialize
    super
    @interpret     =@did_interpret=true
    @javascript    =''
    @context       =''
    @variables     ={} # NO VALUES HERE, but THERE: !
    @variableValues={} #    ={nill: nil}
    @variableTypes ={}
    @svg           =[]
    @lines         =[]
    # @bash_methods=["say"]
    @c_methods     =['printf']
    @ruby_methods  =['puts', 'print'] #"puts"=>x_puts !!!
    @core_methods  =['show', 'now', 'yesterday', 'help'] #difference?
    @modules       ={}
    @classes       ={}
    @methods       ={} # name->method-node
    @OK            ='OK'
    @result        =''
    @listeners     =[]
  end

  def to_s
    "<EnglishParser>"
  end

  # world this method here to resolve the @string
  def init strings
    @no_rollback_depth=-1
    @line_number      =0
    @lines            =strings if strings.is_a? Array
    @lines            =strings.split("\n") if strings.is_a? String
    @string           =@lines[0].strip # Postpone the problem
    @original_string  =@string
    @root             =nil
    @nodes            =[]
    @depth            =0
    @lhs              =@rhs=@comp =nil
    # @result           =nil NOO, keep old!
  end


  def interpretation
    @interpretation=Interpretation.new
    i              = @interpretation #  Interpretation.new
    super # set tree, nodes
    i.javascript  =@javascript
    i.context     =@context
    i.methods     =@methods
    i.ruby_methods=@ruby_methods
    i.variables   =@variables
    i.svg         =@svg
    i.result      =@result
    i
  end

  def root
    many {#root}
      maybe { newline } ||
          maybe { requirements } ||
          maybe { method_definition } ||
          # maybe { ruby_def } || # SHOULD BE just as method_definition !!
          maybe { assert_that } ||
          maybe { block and checkNewline }|| # {x=1;x} todo
          maybe { statement and end_expression } || # x=1+1
          maybe { expressions and end_expression } || # 1+1
          maybe { @result=condition; @comp }|| # 1==1
          maybe { context }
    }
  end

  def set_context context
    @context=context
  end

  def module
    __ %w[module package context gem library] #source
    set_context rest_of_line
  end

  def javascript_require dependency
    require_relative "bindings/js/javascript_auto_libs"
    # require_relative "javascript_auto_libs"
    dependency.gsub!(/.* /, "") # require javascript bla.js
    mapped    =$javascript_libs[dependency]
    dependency=mapped if mapped
    @javascript<<"javascript_require(#{dependency});"
  end

  def includes dependency, type, version
    return javascript_require dependency if dependency.match /\.js$/
    return javascript_require dependency if type and %w[javascript script js].has type
    return ruby_require dependency if not type or %w[ruby gem].has type
  end

  # #{escape_token t}
  def regex x
    match=@string.match(x)
    match||=@string.match(/^\s*#{x}/im)
    raise NotMatching.new(x) if not match
    @string       =match.post_match.strip
    @current_value=match
  end

  def package_version
    _? 'with'
    c=_? comparison_words
    __ 'v', 'version'
    c||=_? comparison_words
    subnode bigger: c
    # @current_value=
    @result=c+" "+regex('\d(\.\d)*')[0]
    _? "or later"
    @result
  end

  #  (:use [native])
  def requirements
    require_types=%w[javascript script js gcc ruby gem header c cocoa native] # todo c++ c# not tokened!
    type         =__? require_types
    __ 'dependencies', 'dependency', 'depends on', 'depends', 'requirement', 'requirements', 'require', 'required',
       'include', 'using',
       'uses', 'needs', 'requires'
    type||=__? require_types
    __? %w[file script header source src]
    __? 'gem', 'package', 'library', 'module', 'context'
    type      ||= __? require_types
    # source? really?
    dependency=quote?
    no_rollback! 5
    # list_of?{packages}
    dependency||= word #regex "\w+(\/\w*)*(\.\w*)*\.?\*?" # rest_of_line
    version   =maybe { package_version }
    includes dependency, type, version if interpreting? rescue nil
    return @result={dependency: {type: type, package: dependency, version: version}}
  end

  def context
    _ 'context'
    @context= word
    newlines
    #NL
    block
    done # done context!!!
  end


  def bracelet
    subnode 'brace' => token('(')
    algebra
    subnode 'brace' => token(')')
  end

  def operator
    tokens(operators)
  end

  def algebra
    must_contain_before [be_words, ',', ';', ':'], operators
    result=value? or bracelet # any { maybe { value } or maybe { bracelet } }
    star {
      op=operator #operator KEYWORD!?! ==> @string="" BUG     4 and 5 == TROUBLE!!!
      no_rollback! if not op=='and'
      # @string=""+@string2 #==> @string="" BUG WHY??
      y=maybe { value } || bracelet
      if interpreting? #and not $use_tree
        y=y.to_f if op == "/" # 3/4==0 ? NOT WITH US!!
        result=do_send(result, op, y||@result) rescue SyntaxError
      end
      result||true # star OK
    }
    return parent_node if $use_tree and not interpreting?
    @result=result
    if $use_tree and @interpret
      tree   =parent_node
      @result=tree.eval_node @variableValues, result if tree rescue result #wasteful!!
    end
    @result
  end

  def current_context
    @context #todo: tree / per node
  end

  # def javascript
  #   script_block?
  #   __ current_context=='javascript' ? 'script' : 'java script', 'javascript', 'js'
  #   no_rollback! 10
  #   @javascript+=rest_of_line+';'
  #   newline?
  #   return @javascript
  #   #block and done if not @javascript
  # end

  def read_block type=nil
    block=[]
    start_block type
    while true do
      break if end_block? type
      block<<rest_of_line
    end
    subnode type||:block => block
  end


  def html_block
    read_block 'html'
  end


  def javascript_block
    block=maybe { read_block('script') } || maybe { read_block('js') } || read_block('javascript')
    @javascript << block.join(";\n")
  end


  def ruby_block
    read_block 'ruby'
  end

  def special_blocks
    html_block? || ruby_block? || javascript_block
  end

  def end_of_statement
    c=checkNewline||end_expression
    # ||end_expression #end_block #newlines
    checkNewline if c and @string.blank?
    c
  end

  # see read_block for RAW blocks! (</EOF> type)
  # EXCLUDING start_block & end_block ! really ?:
  def block #type
    start_block #NEWLINE ALONE == START!?!?!
    @original_string=@string #REALLY??
    start           =pointer
    s               =statement #BUUUUUG~~~!!!
    content         =pointer-start
    allow_rollback
    # newline?
    end_of_statement # danger might act as block end!
    end_of_block =end_block? #tokens? done_words
    if not end_of_block
      star {#One or more
        s       =statement||s
        content =pointer-start
        end_of_statement
      }
      # end_of_statement?
      end_of_block=end_block
    end
    @last_result=@result
    return s if interpreting?
    return content #if not $use_tree
    # if $use_tree
    #   p=parent_node
    #   p.content=content if p
    #   p
    # end
  end


  #direct_token: WITH space!
  #todo: proper token stream, pre-lex'ed
  def token t
    return tokens t if t.is_a? Array
    # encoding: utf-8
    #return nil if checkEnd
    # t=t[0] if t.is_a? Array #HOW TH ?? method_missing
    @string.strip!
    comment_block if @string.start_with? '/*'
    raiseEnd
    if starts_with? t
      @current_value=t.strip
      @string       =@string[t.length..-1]
      if /^\w/.match(@string) and /^\w/.match(t)
        raise NotMatching.new(t+" (strings needs whitespace, special chars don't)")
      else
        @string.strip!
        return @current_value
      end
    else
      verbose 'expected '+t.to_s # if @throwing
      raise NotMatching.new(t)
    end
  end

  #todo: proper token stream, pre-lex'ed
  def tokens *tokenz
    # encoding: utf-8
    raiseEnd
    comment_block if @string.starts_with? '/*'
    string=@string.strip+' '
    for t in tokenz.flatten
      # next if t.is_a Variable
      next if t=='' # todo debug HOW
      return true if (t=="\n" and @string.empty?)
      if t.match(/^\w/)
        match=string.match(/^\s*#{t}/im)
        next if match and match.post_match.match /^\w/ # next must be space or so!
      else #special char
        string=string.fix_encoding
        match =string.match(/^\s*#{escape_token t}/im)
      end
      if match
        x       =@current_value=t
        @string =match.post_match.strip
        @string2=@string
        return x
      end
    end
    raise NotMatching.new(tokenz.to_s) #if @throwing
  end

  def escape_token t
    return t if t=='ƒ'
    t.gsub(/([^\w])/, "\\\\\\1")
  end

  def starts_with tokenz
    return false if checkEndOfLine
    string=@string+' ' # todo: as regex?
    tokenz=[tokenz] if tokenz.is_a? String
    for t in tokenz
      # RUBY BUG?? @string.start_with?(/#{t}[^\w]/)
      if t.match(/\w/)
        return t if string.match(/^#{t}[^\w]/im)
      else
        return t if string.start_with? t #escape_token []
      end
    end
    return false
  end


  def nth_item # Also redundant with property evaluation (But okay as a shortcut)
    set=_? 'set'
    n  =__ numbers+['first', 'last', 'middle']
    _? '.'
    type=__ ['item', 'element', 'object', 'word', 'char', 'character']+type_names # noun
    __ ['in', 'of']
    l =resolve(true_variable?)||list?||quote
    return @result=l.join('')[n.parse_integer-1] if type.match(/^char/)
    l      =l.select { |i| i.is_a type } if type_names.contains type
    @result=l.item(n) # -1 AppleScript style !!! BUT list[0] !!!
    if set
      _ "to"
      val                 =endNode
      l[n.parse_integer-1]=do_evaluate(val)
    end
    return @result
  end

  def listSelector
    return nth_item? || functionalSelector
  end

  # DANGER: INTERFERES WITH LIST?, NAH, NO COMMA: {x > 3}
  def functionalSelector
    _ '{'
    xs  =true_variable
    crit=selector
    _ '}'
    filter(xs, crit)
  end

  def list check=true
    raise NotMatching.new if @string[0]==','
    must_contain_before [be_words, operators-['and']], ',' if check #,before:
    # +[' '] ???
    start_brace= __? '[', '{', '(' #only one!
    raise NotMatching.new 'not a deep list' if not start_brace and (@inside_list)

    #all<<expression(start_brace)
    # $verbose=true #debug
    @inside_list=true
    first       =endNode?
    @inside_list=false if not first
    raise_not_matching if not first
    all =[first]
    star {
      tokens(',', 'and') # danger: and as plus! BAD IDEA!!!
      all<<endNode
      #all<<expression
    }
    _ ']' if start_brace=='['
    _ '}' if start_brace=='{'
    _ ')' if start_brace=='('
    @inside_list  =false
    @current_value=all
    all
  end

  def minusMinus
    must_contain '--'
    v=variable
    _ '--'
    @result           =do_evaluate(v, v.type)+1 if @interpret
    @variableValues[v]=v.value=@result
  end

  def plusPlus
    must_contain '++'
    v=variable
    _ '++'
    return parent_node if not @interpret
    @result                =do_evaluate(v, v.type)+1
    @variableValues[v.name]=v.value=@result
  end

  def selfModify
    maybe { plusEqual } ||maybe { plusPlus } || minusMinus
  end

  def plusEqual
    must_contain '|=', '&=', '&&=', '||=', '+=', '-=', '/=', '^=', '%=', '#=', '*=', '**=', '<<', '>>'
    v  =variable
    mod=__ '|=', '&=', '&&=', '||=', '+=', '-=', '/=', '^=', '%=', '#=', '*=', '**=', '<<', '>>'
    val=v.value
    exp=expressions # value
    arg=do_evaluate(exp, v.type)
    return parent_node if not interpreting?
    @result                =val|arg if mod=='|='
    @result                =val||arg if mod=='||='
    @result                =val&arg if mod=='&='
    @result                =val&&arg if mod=='&&='
    @result                =val+arg if mod=='+='
    @result                =val-arg if mod=='-='
    @result                =val*arg if mod=='*='
    @result                =val**arg if mod=='**='
    @result                =val/arg if mod=='/='
    @result                =val%arg if mod=='/='
    @result                =val<<arg if mod=='<<'
    @result                =val>>arg if mod=='>>'
    @variableValues[v.name]=@result
    v.value                =@result
  end

  def swift_hash
    _ '['
    h={}
    star {
      _ ',' if h.length>0 # not h.blank?
      __? '"', "'" # optional quotes
      key=word
      __? '"', "'"
      _ ':'
      @inside_list       =true
      # h[key] = expression0 # no
      h[key.to_s.to_sym] = expressions # no
    }
    _ ']'
    @inside_list=false
    h
  end

  def close_bracket #for nice GivingUp
    _ '}'
  end

  def json_hash
    must_contain ":", "=>", before: "}"
    # z=regular_json_hash? or immediate_json_hash RUBY BUG! or and || act very differently!
    z=regular_json_hash? || immediate_json_hash
    z
  end

  # colon for types not Compatible? puts a:int vs puts {a:int} ? maybe egal
  # careful with blocks!! {puts "s"} VS {a:"s"}
  def regular_json_hash
    _ '{'
    _? ':' and no_rollback! #{:a...} Could also mean list of symbols? Nah
    h={}
    star {
      _? ';' or _ ',' if h.length>0 # not h.blank?
      quoted=__? '"', "'" # optional
      key   =word
      __ '"', "'" if quoted
      _? '=>' or _? '=' or #  todo a{b=c} vs a{b:c} Property versus hash !!
          starts_with?("{") or _? '=>' or _ ':'
      @inside_list       =true
      # h[key] = expression0 # no
      h[key.to_s.to_sym] = expressions # no
    }
    # no_rollback!
    close_bracket
    @inside_list=false
    h
  end

  # expensive?
  # careful with blocks/closures ! map{puts it} VS data{a:"b"}
  def immediate_json_hash # a:{b} OR a{b:c}
    # must_contain_before ":{", ":"
    w=word #expensive
    # starts_with?("={") and _? '=' or # todo set a to {b=>c} vs a:{b:c}
    starts_with?("{") or _ '=>' #or _ ':' disastrous :  BLOCK START!
    no_rollback!
    r=regular_json_hash
    {w.to_sym => r} # AH! USEFUL FOR NON-symbols !!!
  end

  # keyword expression is reserved by ruby/rails!!! => use hax0r writing or plural
  def expressions fallback=nil
    # raiseNewline ?
    start  =pointer
    @result= ex =any {#expression}
      maybe { algebra } ||
          maybe { json_hash } ||
          maybe { swift_hash } || # really?
          maybe { evaluate_index } ||
          maybe { listSelector } ||
          maybe { list } ||
          maybe { evaluate_property } ||
          maybe { selfModify } ||
          maybe { endNode }
      # ||['one'].has(fallback) ? 1 : false # WTF todo better quantifier one beer vs one==1
    }
    return pointer-start if not interpreting? and not $use_tree
    @last_result=@result=do_evaluate ex if ex and interpreting? rescue SyntaxError
    if @result.blank? or @result==SyntaxError and not ex==SyntaxError
      # keep false
    else
      ex=@result
    end

    # NEIN! print 'hi' etc etc
    # more=expression0? if @result.is_a? Quote
    # more||=quote? #  "bla " 7 " yeah"
    # more+=expression0? if more.is_a? Quote rescue ""
    # ex+=more if more
    # subnode expression: ex
    return @result=ex
  end

  def piped_actions
    return false if @in_pipe
    must_contain "|"
    @in_pipe=true
    a       =statement
    _ '|'
    no_rollback!
    c=true_method or bash_action
    args=star { arg }
    args=[args, Argument.new(value: a)] if c.is_a? Method #with owner
    puts do_send(a, c, args) if interpreting?
  end

  def aliases
    _ 'alias'
    aliaz=word
    ref  =word
    @methods.put aliaz, @methods[ref] if @methods.has ref
    @variables.put aliaz, @variables[ref] if @variables.has ref
    @classes.put aliaz, @classes[ref] if @classes.has ref
  end

  def statement
    raiseNewline #really? why?
    x           =any {#statement}
      return @NEWLINE if checkNewline
      maybe { loops }||
          maybe { if_then_else } ||
          # maybe { if_then } ||
          maybe { once } ||
          maybe { piped_actions } ||
          maybe { declaration } ||
          maybe { setter } ||
          maybe { aliases } ||
          maybe { returns } ||
          maybe { breaks } ||
          maybe { constructor } ||
          maybe { action } ||
          maybe { expressions } # AS RETURN VALUE! DANGER!
    }
    @last_result=x if x
    # @last_result||=x
    #one :action, :if_then ,:once , :looper
    #any{action || if_then || once || looper}
  end

  def exceptionTypes
    word
    star{ _',' ; word }
  end

  def method_definition
    # annotations=annotations?
    # modifiers=modifiers?
    tokens method_tokens #  how to
    no_rollback!
    name= noun? or verb #  integrate or word
    # obj=maybe { endNode } # a sine wave  TODO: invariantly get as argument book.close==close(book)
    _? '('
    arg_nr=1
    args  =star {
      @in_params=true
      a         =arg(arg_nr)
      arg_nr    =arg_nr+1
      _? ','
      a
    } # over an interval
    return_type=__?('as', 'return', 'returns', 'returning') and typeNameMapped?
    return_type||=typeNameMapped if _? '->' #_? '!' # swift style --
    @in_params =false
    _? ')'
    __? 'raises','throws' and exceptionTypes
    allow_rollback # for
    dont_interpret!
    b   =action_or_block # define z as 7 allowed !!!
    args=[args] if args.is_a?(Argument)
    f   =Function.new name: name, arguments: args, return_type: return_type, body: b, scope: self
    #,modifiers:modifiers, annotations:annotations
    @methods[name]=f||parent_node||b rescue nil # with args! only in tree mode!!
    f || name
  end

  def ruby_action
    _ 'ruby'
    a=action || quote
    exec(a) if interpreting?
  end

  def raise_not_matching msg=nil
    raise NotMatching.new msg
  end

  def bash_action
    require_relative "bindings/shell/bash-commands"
    ok=starts_with (['bash'] + $bash_commands)
    raise_not_matching "no bash commands" if not ok
    remove_tokens 'execute', 'command', 'commandline', 'run', 'shell', 'shellscript', 'script', 'bash'
    @command = maybe { quote } # danger bash "hi">echo
    @command ||= rest_of_line
    subnode bash: @command
    #any{ try{  } ||  statements }
    if interpreting?
      begin
        puts 'going to execute ' + @command
        result=%x{#{@command}}
        puts 'result:'
        puts result
        return result ? result.split("\n") : true
      rescue
        puts 'error executing bash_action'
      end
    end
    false
  end


  def if_then_else
    ok      =maybe { if_then } #todo : if 1 then false else 2 => 2 :(
    ok      ||=action_if
    ok      = :false if ok==false
    o       =maybe { otherwise } || :false
    @result = ok!="OK" ? ok : o
  end

  def action_if
    must_contain 'if'
    a=action_or_expressions
    _ 'if'
    c=condition_tree
    if interpreting?
      if check_condition c
        return do_execute_block a
      else
        return @OK #false but block ok!
      end
    end
    return a
  end

  def if_then
    __ if_words
    no_rollback! # 100
    c=condition_tree
    raise InternalError.new "no condition_tree" if c==nil
    # c=condition
    _? 'then'
    dont_interpret! #if not c  else dont do_execute_block twice!
    b= expression_or_block #action_or_block
    # o=otherwise?
    # b=block if use_block # interferes with @comp/condition
    # b=statement if not use_block
    # b=action if not use_block
    allow_rollback
    if interpreting?
      if check_condition c
        return do_execute_block b
      else
        return @OK #  o|| false but block ok!
      end
    end
    return b
  end

  def once_trigger
    __ once_words
    dont_interpret!
    c=condition
    no_rollback!
    _? 'then'
    use_block=start_block?
    b=action and end_expression if not use_block
    b=block and done if use_block
    add_trigger c, b
  end

  def action_once
    must_contain once_words # if not _do and newline
    no_rollback!
    b=action_or_block
    # _do=_? 'do'
    # dont_interpret!
    # b=action if not _do
    # b=block and done? if _do
    __ once_words
    c=condition
    end_expression
    add_trigger c, b
  end


  def once
#	|| 'as soon as' condition \n block 'ok'
#	|| 'as soon as' condition 'then' action;
    maybe { once_trigger } || action_once
#	|| action 'as soon as' condition
  end

  #/*n_times
  #	 verb number 'times' preposition nod -> "<verb> <preposition> <nod> for <number> times" 	*/
  #/*	 verb number 'times' preposition nod -> ^(number times (verb preposition nod)) # Tree ~= lisp	*/
  def verb_node
    v=verb
    nod
    raise UnknownCommandError.new 'no such method: '+v if !@methods.contains(v)
    return v
    #end_expression
  end

  def spo
    # NotImplementedError
    return false if not $use_wordnet
    raise NotMatching.new("$use_wordnet==false") if not $use_wordnet
    s=endNoun
    p=verb
    o=nod
    return do_send(s, p, o) if @interpret
  end

  def substitute_variables args
    #args=" "+args+" "
    for variable in @variableValues.keys
      variable=variable.join(' ') if variable.is_a? Array #HOW!?!?!
      value   =@variableValues[variable]||'nil'
      #args.gsub!(/\$#{variable}/, "#{variable}") # $x => x !!
      args.gsub!(/.\{#{variable}\}/, "#{value}") #  ruby style #{x} ;}
      args.gsub!(/\$#{variable}$/, "#{value}") # php style $x
      args.gsub!(/\$#{variable}([^\w])/, "#{value}\\\1")
      args.gsub!(/^#{variable}$/, "#{value}")
      args.gsub!(/^#{variable}([^\w])/, "#{value}\\1")
      args.gsub!(/([^\w])#{variable}$/, "\\1#{value}")
      args.gsub!(/([^\w])#{variable}([^\w])/, "\\1#{value}\\2")
    end
    #args.strip
    args
  end

  # todo : why special? direct eval, rest_of_line
  def ruby_method_call
    call=tokens? 'call', 'execute', 'run', 'start', 'evaluate', 'invoke'
    no_rollback! if call # remove later
    ruby_method=tokens? @ruby_methods+@core_methods
    raise UndefinedRubyMethod.new word if not ruby_method
    args=rest_of_line
    # args=substitute_variables rest_of_line
    checkNewline
    return do_call_ruby_method(ruby_method, args) if interpreting?
    #raiseEnd
    subnode method: ruby_method #why not auto??
    subnode args: args
    return @current_value=ruby_method
    # return Object.method ruby_method.to_sym
    # return Method_call.new ruby_method,args,:ruby
  end

  def is_object_method m
    return true if m.is_a? Method and m.receiver==Object
    object_method = Object.method(m) rescue false #if Object.method_defined?(m) NOO : puts
    if object_method
      return object_method
    end
    return false
  end

  # Object.constants  :IO, :STDIN, :STDOUT, :STDERR ...:Complex, :RUBY_VERSION ...
  def has_object m
    object_method = Object.method(m) rescue false
    if object_method # Bad approach:  that might be another method Tree.beep!
      method=Object.method(m) # todo: find OTHER! not just Object.
      # return method # false:  if Object has method assume no object has method BAAAD!!!!
      return false
    end
    return true
  end

  def has_args method, clazz=Object, assume=false
    #todo MATCH!   [[:req, :x]] -> required: x
    return method.arity>0 if method.is_a? Method
    clazz         =clazz.class if not clazz.is_a? Class #lol
    object_method = clazz.method(method) if clazz.method_defined?(method) rescue false
    object_method = clazz.public_instance_method(method) if not object_method rescue false
    if object_method # Bad approach:  that might be another method Tree.beep!
      # puts "has_args method.parameters : #{object_method} #{object_method.parameters}"
      return true if object_method.arity<0 and assume # possible! DEFAULT ARGS
      return object_method.arity>0
    end
    return false if method.in ['invert', '++', '--'] # increase by 8

    return assume #false # true
  end

  def c_method
    tokens @c_methods
  end

  def builtin_method
    w=word
    raise_not_matching "no word" if not w
    raise_not_matching "capitalized #{w} no builtin_method" if w.capitalize==w
    m=Object.method(w) rescue nil
    m||=HelperMethods.method(w) rescue nil
    m
    # m ? m.name : nil
  end

  def true_method
    no_keyword
    should_not_start_with auxiliary_verbs
    # tokens?(@methods.keys+"ed") sorted files -> sort files ?
    v=c_method? || verb? || tokens?(@methods.keys) || tokens?(@ruby_methods) || tokens?(@core_methods) || builtin_method?
    raise NotMatching.new 'no method found' if not v
    v #.to_s
  end

  def strange_eval obj
    _? '('
    args=star { arg }
    _ ')'
    @result=eval_string("#{obj}(#{args})")
    @result
  end

  # conflict with files, 3.4
  def thing_dot_method_call
    must_contain_before ['='], '.' # before...?
    obj=endNode
    return strange_eval obj if _? '(' and interpreting?
    _ '.'
    method_call obj
  end

  def call_arguments #todo:named args etc!
    endNode #may be list
  end

  def method_call obj=nil
    # ruby_method_call? ||
    thing_dot_method_call? || generic_method_call(obj)
  end

  # read mail or bla(1) or a.bla(1)  vs ruby_method_call !!
  def generic_method_call obj=nil
    #verb_node
    method      =true_method
    start_brace =__? '(', '{' # '[', list and closure danger: index
    # todo  ?merge with list?
    no_rollback! if start_brace
    if is_object_method(method) #todo !has_object(method) is_class_method
      obj||=Object
    else
      _? 'of'
      obj=maybe { nod? } if @in_args
      obj=maybe { nod? || list } if not @in_args # todo: expression
      # print sorted files
      # obj=maybe { nod? || list? || expression } if not @in_args # todo: expression
    end
    assume_args=true #!starts_with("of")  # true    #<< Redundant with property eventilation!
    if has_args(method, obj, assume_args) # NOT KNOWN YET!!
      @current_value=nil
      @in_args      =true
      args          =call_arguments? #todo:named args etc!
      if not args and is_object_method(method) #and c_method or static etc
        args =obj
        obj  =Object
      end
      # __? ',','and'
    else
      more=_? ','
      obj =[obj]+list(false) if more
    end
    @in_args=false
    _ ')' if start_brace=='('
    _ ']' if start_brace=='['
    _ '}' if start_brace=='{'
    subnode object: obj
    subnode arguments: args
    return FunctionCall.new name: method, arguments: args, object: obj if not interpreting? #parent node!!!
    @result=do_send(obj, method, args) if interpreting?
    return @result
  end

  def bla
    tokens? bla_words
  end

  def applescript
    tokens 'tell application', 'tell app'
    no_rollback!
    app    =quote
    @result="tell application \"#{app}\""
    if _? 'to'
      @result+=' to '+rest_of_line() # "end tell"
    else #Multiline
      while @string and not @string.contains 'end tell'
        # #TODO deep blocks! simple 'end' : and not @string.contains 'end'
        @result+= rest_of_line() +"\n"
      end
      # tokens? "end tell","end"
    end
    # @result        +="\ntell application \"#{app}\" to activate" # to front
    # -s o /path/to/the/script.scpt
    @current_value = %x{/usr/bin/osascript -ss -e $'#{@result}'} if @interpret
    return @result # autowrap-> Script(body:@result,type:osascript)
  end

  def assert_that
    _ 'assert'
    _? 'that'
    what   =rest_of_line
    @result=assert what
  end

  def arguments
    star { arg }
  end

  def constructor
    _? 'create'
    the?
    _ 'new'
    # clazz=word #allow data
    clazz=class_constant
    do_send clazz, :new, arguments
    # clazz=Class.new
    # variables[clazz]=
    # clazz.new arguments
  end

  def returns
    _ 'return'
    @result=expressions?
    @result
  end

  def breaks
    __ 'next', 'continue', 'break', 'stop'
  end

  #	||'say' x=(.*) -> 'bash "say $quote"'
  def action
    start=pointer
    bla?
    result=any {#action
      maybe { special_blocks } ||
          maybe { applescript } ||
          maybe { bash_action } ||
          maybe { evaluate } ||
          maybe { returns } || # Statement Shortcut, until if supports Statements
          maybe { selfModify } ||
          maybe { method_call } ||
          maybe { spo }
      #try { verb_node } ||
      #try { verb }
    }
    raise NoResult.new if not result
    ende=pointer
    # newline? #cut rest, BUT:
    return ende-start if not $use_tree and not @interpret
    return result
  end


  def action_or_block # expression_or_block ??
    # dont_interpret  # always?
    # not @string.blank?
    a=maybe { action } if not starts_with [':', 'do', '{']
    return a if a
    # type=start_block && newline?
    b=block
    # end_block
    return b
  end

  def expression_or_block # action_or_block
    # dont_interpret  # always?
    a=maybe { action }||maybe { expressions }
    return a if a
    b=block
    return b
  end

  def end_block type=nil
    done type
  end

  def done type=nil
    return @OK if type and close_tag? type
    return @OK if checkEndOfLine
    newline?
    ok=tokens done_words
    token type if type #optional?
    ignore_rest_of_line!
    ok
  end

  # used by done / end_block
  def close_tag type
    _ '</'
    _ type
    _ '>'
  end

  def datetime
    # Complicated stuff!
    # later: 5 secs from now  , _ 5pm == AT 5pm
    must_contain time_words
    _kind = tokens event_kinds
    no_rollback!
    __? 'around', 'about'
    # require 'chronic_duration'
    # WAH! every second  VS  every second hour WTF ! lol
    n    =number? || 1 # every [1] second
    _to  = maybe { tokens 'to', 'and' }
    _to  =number if _to
    _unit=__ time_words # +["am"]
    _to  ||= __? 'to', 'and'
    _to  ||=number? if _to
    return Interval.new(_kind, n, _to, _unit)
  end

  def collection
    any {#collection }
      maybe { range } ||
          maybe { true_variable } ||
          action_or_expressions #of type list !!
    }
  end


  def for_i_in_collection
    _? 'repeat'
    __('for', 'with')
    _? 'all'
    v=variable # selector !
    __('in', 'from')
    c=collection
    b=action_or_block
    for i in c
      v.value=i
      do_execute_block b
    end if interpreting?
  end


  # todo vs checkNewline ??
  def end_expression
    checkEndOfLine||__?(newline_tokens)||newline
  end

  #  until_condition ,:while_condition ,:as_long_condition


  def assure_same_type var, type
    oldType=@variableTypes[var.name]
    # begin
    raise WrongType.new "#{oldType} #{type}" if oldType and type and not type<=oldType
    raise WrongType.new "#{oldType} #{var.type}" if oldType and var.type and not var.type<=oldType
    # raise WrongType.new "#{type} #{var.type}" if type and var.type and not var.type>=type
    raise WrongType.new "#{type} #{var.type}" if type and var.type and not (var.type<=type|| var.type>=type)
    # rescue
    #   p $!
    # end
    var.type=type
  end


  def assure_same_type_overwrite var, val
    oldType=var.type
    raise WrongType.new "#{var} #{val}" if oldType and not val.type.is_a oldType
    raise ImmutableVaribale.new if var.final and var.value and not val.value==var.value
    var.value=val
  end

  def boolean
    b      =tokens 'true', 'false'
    @result=(b=='true') ? :true : :false
    # @result=b=='true'
    @result
    # @OK
  end

  def class_constant
    c=word
    c=Object.const_get(c) if interpreting?
    c
    # raise NameError "uninitialized constant #{c}" unless Object.const_defined? c
  end

  def get_obj o
    return false if not o
    eval(o) rescue variables[o]
  end

  # Object.property || object.property
  def property
    must_contain_before ' ', "."
    no_rollback!
    owner=class_constant rescue nil
    owner=get_obj(owner)||variables[true_variable].value #reference
    _ '.'
    properti=word
    Property.new name: properti, owner: owner
  end

  def declaration
    should_not_contain '='
    # must_contain_before  be_words+['set'],';'
    a   =the?
    mod =modifier?
    type=typeNameMapped
    tokens? 'var', 'val', 'value of'
    mod ||=modifier? # public static ...
    var =property? || variable(a)
    assure_same_type var, type
    # var.type     ||=type
    var.final    =const.contains(mod)
    var.modifier =mod
    return var
  end


  def auto_type val
    return val.class if not val.is_a? String
    return val.name if not val.is_a? TreeNode
    return do_evaluate(val).class
  end

  #  CAREFUL WITH WATCHES!!! THEY manipulate the current system, especially variable
  #/*	 let nod be nods */
  def setter
    must_contain_before ['>', '<', '+', '-', '|', '/', '*'], be_words+['set']
    _let=no_rollback! if let?
    a   =the?
    mod =modifier?
    type=typeNameMapped?
    tokens? 'var', 'val', 'value of','variable'
    mod  ||=modifier? # public static ...
    var  =property? || variable(a)
    # _?("always") => pointer
    setta=_?('to') || be # or not_to_be 	contain -> add or create
    # do_interpret!
    val  =adjective? || expressions
    no_rollback!
    val     =[val].flatten if setta=='are' or setta=='consist of' or setta=='consists of'
    var.type||=type||auto_type(val)
    assure_same_type_overwrite var, val if _let
    # var.type||=type||val.class #eval'ed! also x is an integer
    # assure_same_type var, type||val.class if check_interpret # todo : type analysis via tree
    @variableValues[var.name] =val #this might be nonsense if it is not interpreting
    var.value                 =val
    if @interpret and (not @variableValues.contains(var.name) or mod!='default')
      var.owner.send(var.name+"=", val) if var.is_a? Property #todo
    end
    var.final    =const.contains(mod)
    var.modifier =mod
    @result      =val
    # end_expression via statement!
    # return var if @interpret

    subnode var: var
    subnode val: val
    return val if interpreting?
    return var
    # return parent_node if $use_tree
    # return old-@string if not @interpret # for repeatable, BAD
    # ||'to'
    #'initial'?	let? the? ('initial'||'var'||'val'||'value of')? variable (be||'to') value
  end

  # a=7
  # a dog=7
  # Int dog=7
  # my dog=7
  # a green dog=7
  # an integer i
  def isType x
    return true if x.is_a? Class
    return true if type_names.contains x
    return false
  end

  # already existing
  def variable a=nil
    a  ||=article?
    a  =nil if a!='a' #hack for a variable
    typ=typeNameMapped? # DOESN'T BELONG HERE!  e.g. int i++
    p  =__? possessive_pronouns
    # all=p ? [p] : []
    all=one_or_more { word } rescue (a=='a' ? all=[a] : (raise NotMatching))
    raise_not_matching if not all or all[0]==nil
    name =all.join(' ')
    name =all[1..-1].join(' ') if !typ&&all.length>1&&isType(all[0]) #(p ? 0 : 1)
    name =p+' '+name if p
    name.strip!
    oldVal=@variableValues[name]
    # {variable:{name:name,type:typ,scope:@current_node,module:current_context}}
    return @variables[name] if @variables[name] # DONT EVAL HERE! DONT PUT VALUES HERE (IN TEST)
    @result         =Variable.new name: name, type: typ, scope: @current_node, module: current_context, value: oldVal
    @variables[name]=@result
    # @variables[p+' '+name]=@result if p
    @result
  end

  def word include=[]
    #danger:greedy!!!
    no_keyword_except include
    raiseNewline
    #raise EndOfDocument.new if @string.blank?
    #return false if starts_with? keywords
    match=@string.match(/^\s*[a-zA-Z]+[\w_]*/)
    if (match)
      @string       =@string[match[0].length..-1].strip
      @current_value=match[0].strip
      return match[0]
    end
    #fad35
    #unknown
    # noun
  end

  # NOT SAME AS should_not_start_with!!!
  def should_not_contain words
    for w in [words].flatten
      if w.match(/^\w/)
        bad=@string.match(/^\w#{w}^\w/im)
      else
        if @string.match /;/
          bad=@string.match /#{escape_token(w)}.*?;/
        else
          bad=@string.match /#{escape_token(w)}/
        end
      end
      if bad
        raise ShouldNotMatchKeyword.new w
      end
    end
  end

  def must_not_start_with words
    should_not_start_with words
  end

  def should_not_start_with words
    bad=starts_with? words
    return @OK if not bad
    verbose "should_not_match DID match #{bad}" if bad
    raise ShouldNotMatchKeyword.new bad if bad
  end

  def no_keyword_except except=[]
    should_not_start_with keywords-except
  end

  def no_keyword
    no_keyword_except []
  end

  def constant
    tokens constants
  end

  def it
    __ result_words
    return @last_result
  end

  def cast x, typ
    return do_cast x, typ if interpreting?
    return Cast(x, typ)
  end

  def value
    @current_value=nil
    no_keyword_except constants+numbers+result_words+nill_words+['+', '-']
    @result=@current_value=x=any {
      maybe { quote }||
          maybe { nill } ||
          maybe { number } ||
          maybe { true_variable } ||
          maybe { boolean }||
          maybe { constant }||
          maybe { it }||
          maybe { nod }
      #rest_of_line # TOOBIG HERE!
    }
    typ    =typeNameMapped if _?('as')
    x      =cast(x, typ) if typ
    x
  end


  def nod #options{generateAmbigWarnings=false}
    maybe { number } ||
        maybe { quote } ||
        maybe { true_variable } ||
        maybe { the_noun_that } #||
    #try { variables_that } # see selectable
  end

  def article
    tokens articles
  end

  def number_or_word
    number?||word
  end

  def arg position=1 # about sex
    pre=preposition? ||"" #  might be superfluous if calling "BY"
    article? #todo use a vs the ?
    a=variable?
    return Argument.new name: a.name, type: a.type, preposition: pre, position: position if a
    type=typeNameMapped?
    v   =endNode?
    name=pre+ (a ? a.name : type||"") # daring! def integrate(number) !!
    return false if name.blank?
    Argument.new preposition: pre, name: name, type: type, position: position, value: v
  end


  # BAD after filter, ie numbers [ > 7 ]
  # that_are bigger 8
  # whose z are nonzero
  def compareNode
    c=comparison
    raise NotMatching.new "NO comparison" if not c
    raise NotMatching.new 'compareNode = not allowed' if c=='=' #todo Why not / when
    @rhs=endNode # expression
  end

  def whose
    _ 'whose'
    endNoun
    compareNode # is bigger than live
  end

  # things that stink
  # things that move backwards
  # people who move like Chuck
  # the input, which has caused problems
  #images which only vary horizontally
  def that_do
    __ 'that', 'who', 'which'
    star { adverb } # only
    @comp=verb # live
    _? 's' # lives
    star { adverb?||# happily
        preposition? || # in
        endNoun? # africa
    }
  end

  # more easisly
  def more_comparative
    __ 'more', 'less', 'equally' # comparison_words
    adverb
  end


  def as_adverb_as
    _ 'as'
    adverb
    _ 'as'
  end

  # 50% more
  # "our burgers have more flavor",
  # "our picture is sharper"
  # "our picture runs sharper"
  def null_comparative
    verb
    comparative
    endNode?
    return c if c.start_with? 'more' or c.ends_with? 'er'
  end

  #  faster than ever
  #  more funny than the funny cat
  def than_comparative
    comparative
    _ 'than'
    adverb? || endNode
  end


  def comparative
    c=more_comparative? or adverb
    @comp=c if c.start_with? 'more' or c.ends_with? 'er'
  end


  def that_are
    __ 'that', 'which', 'who'
    be
    maybe { compareNode }|| # bigger than live
        @comp=adjective? || # simple
            gerund #  whining
    @comp
  end

  # things that I saw yesterday
  def that_object_predicate
    tokens 'that', 'which', 'who', 'whom'
    pronoun? or endNoun
    verbium
    star {
      adverb? || preposition? || endNoun?
    }
  end


  def that
    filter=maybe { that_do } ||maybe { that_are }|| whose
  end


  def where
    tokens 'where' # NOT: ,'who','whose','which'
    condition
  end

  # ambivalent?  delete james from china

  def selector
    return if checkEndOfLine
    x=maybe { compareNode }||
        maybe { where }|| # sql style
        maybe { that } || # friends that live in africa
        maybe { token('of') and endNode }|| # friends of africa
        preposition and nod # friends in africa
    $use_tree ? parent_node : @current_value
    x
  end


  # preposition nod  # ambivalent?  delete james, from china delete (james from china)

  # (who) > run like < rabbits
  # contains
  def verb_comparison
    star { adverb }
    @comp=verb # WEAK !?
    preposition?
    @comp
  end


  def comparison # WEAK pattern?
    @comp=maybe { verb_comparison }|| # run like , contains
        comparation # are bigger than
  end


  # is more or less
  # is neither ... nor ...
  # are all smaller than ...
  # Comparison phrase
  def comparation
    # danger: is, is_a
    eq =tokens? be_words
    _? 'all'
    start=pointer
    tokens? 'either', 'neither'
    @not=tokens? 'not'
    maybe { adverb } #'quite','nearly','almost','definitely','by any means','without a doubt'
    if (eq) # is (equal) optional
      comp=tokens? comparison_words
    else
      comp=tokens comparison_words
      no_rollback!
    end
    _? 'to' if eq
    tokens? 'and', 'or', 'xor', 'nor'
    tokens? comparison_words # bigger or equal != different to condition_tree true or false
    @comp=comp ? pointer-start : eq
    _? 'than' #, 'then' #_?'then' ;} danger: if Jens.smaller then ok
    subnode comparation: @comp
    @comp
  end

  def either_or
    tokens? 'be', 'is', 'are', 'were'
    tokens 'either', 'neither'
    comparation?
    value
    tokens? 'or', 'nor'
    comparation?
    value
  end

  def is_comparator c
    return false if not c.is_a? String
    # puts "is_comparator #{c}"
    ok=comparison_words.contains(c)
    ok||=comparison_words.contains(c-"is ") ||
        comparison_words.contains(c-"are ") ||
        comparison_words.contains(c-"the ") ||
        class_words.contains(c) #rescue false
    ok
  end


  def check_list_condition quantifier
    # return true if not @a.is_a?Array # every one is evil
    # see quantifiers
    begin
      count=0
      @comp.strip!
      for item in @lhs
        @result=do_compare(item, @comp, @rhs) if is_comparator @comp
        @result=do_send(item, @comp, @rhs) if not is_comparator @comp
        break if !@result and ['all', 'each', 'every', 'everything', 'the whole'].matches quantifier
        break if @result and ['either', 'one', 'some', 'few', 'any'].contains quantifier
        if @result and ['no', 'not', 'none', 'nothing'].contains quantifier
          @not=!@not
          break
        end
        count=count+1 if @result # "many", "most" : continue count
      end

      min    =@lhs.length/2
      @result=count>min if quantifier=='most'||quantifier=='many'
      @result=count>=1 if quantifier=='at least one'
      # todo "at least two","at most two","more than 3","less than 8","all but 8"
      @result=!@result if @not
      if not @result
        verbose "condition not met #{@lhs} #{@comp} #{@rhs}"
      end
      return @result
    rescue => e
      #debug x #soft message
      error e #exit!
    end

    return false
  end

  def check_condition cond=nil, negate=false #later:node?
    return true if cond==true || cond==:true #EVALUATED BEFORE!!!
    return false if cond==false || cond==:false #EVALUATED BEFORE!!!
    return cond if cond!=nil and not cond.is_a? TreeNode and not cond.is_a? String
    # cond==nil ||
    # return false if cond==false #EVALUATED BEFORE!!!
    begin
      # else use state variables todo better!
      if cond.is_a? TreeNode
        @lhs =cond[:expressions]
        @rhs =cond.all(:expressions).reject { |x| x==false }[-1]
        @comp=cond.all(:comparation).reject { |x| x==false }[-1]
        # @comp=cond[:comparation]
      end
      return false if not @comp #todo!
      @lhs.strip! if @lhs and @lhs.is_a? String # nil==nil ok
      @rhs.strip! if @rhs and @rhs.is_a? String # " a "=="a" !?!?!? NOOO! why?
      @comp.strip!
      if is_comparator @comp
        result=do_compare(@lhs, @comp, @rhs)
      else
        result=do_send(@lhs, @comp, @rhs)
      end
      # if !result and not cond.blank? #HAAACK DANGARRR
      #   #@a,@comp,@b= extract_condition c if c
      #   evals=''
      #   @variables.each { |var, val| evals+= "#{var}=#{val};" }
      #   result=eval(evals+cond.join(' ')) #dont set @result here (i.e. while(...)last_result )
      # end
      result=!result if @not
      result=!result if negate # XOR result=result ^ negate
      if not result
        verbose "condition not met #{cond} #{@lhs} #{@comp} #{@rhs}"
        # result=:false why? #incompatible with 'while (check_condition c)'
      end
      return result
    rescue => e
      #debug x #soft message
      error e #exit!
    end
    return false
  end

  def action_or_expressions fallback=nil
    maybe { action }||
        expressions(fallback)
    # maybe{expressions(fallback)}
    # expressions(fallback)
  end

  # all of 1,2,3
  # all even numbers in [1,2,3,4]
  # one element in 1,2,3
  def element_in
    noun?
    __ "in", "of"
  end

  def condition
    start     =pointer
    brace     =_? '('
    negated   =_? 'not'
    brace     ||=_? '(' if negated
    # @a=endNode # NO LISTS (YET)! :(
    quantifier=maybe { tokens quantifiers } # vs selector!
    element_in? if quantifier # -> selector!
    @lhs =action_or_expressions quantifier
    @not =false
    @comp=use_verb=maybe { verb_comparison } # run like , contains
    @comp=maybe { comparation } unless use_verb # are bigger than
    # allow_rollback # upto where??
    @rhs =action_or_expressions nil if @comp # optional, i.e.   return true IF 1
    _ ')' if brace
    negate = (negated||@not)&& !(negated and @not)
    subnode negate: negate
    return @lhs if not @comp and not @rhs
    # return negate ? !@lhs : @lhs if not @comp # optional, i.e.   return true IF 1

    # 1,2,3 that are smaller 4  VS 1,2,3 contains 4
    quantifier||="all" if @lhs.is_a? Array and not @lhs.respond_to?(@comp) and not @rhs.is_a? Array
    # return  negate ? !@a : @a if not @comp
    if interpreting?
      return negate ? (!check_list_condition(quantifier)) : check_list_condition(quantifier) if quantifier
      return negate ? (!check_condition) : check_condition # nil
    end
    # return Condition.new lhs:@a,cmp:@comp,rhs:@b
    return start-pointer if not $use_tree
    return parent_node if $use_tree
  end


  def condition_tree recurse=true
    brace=_? '('
    _? 'either' # todo don't match 'either of'!!!
    # negate=_? "neither"
    c=condition_tree false if brace and recurse
    c=condition if not brace
    star {
      op=__ 'and', 'or', 'nor', 'xor', 'nand', 'but'
      c2=condition_tree false if recurse
      return @current_node if not interpreting? # or $use_tree
      c||= c2 if op=='or'
      #NIL c = c or c2 if op=='or' RUBY BUG!?!?!
      # c =c and c2 if op=='and' || op=='but'
      c&&= c2 if op=='and' || op=='but'
      c&&= !c2 if op=='nor'
      return c||false
    }
    _ ')' if brace
    c
  end

  def otherwise
    newline?
    must_contain 'else', 'otherwise'
    __? 'else', 'otherwise'
    # else if ... ! OK?
    e=expressions
    __? 'else', 'otherwise' and newline
    e
  end

  # todo  I hate to ...
  def loveHateTo
    _? 'would', "wouldn't"
    __? 'do', 'not', "don't"
    __ ['want', 'like', 'love', 'hate']
    _ 'to'
  end


  def gerundium
    verb
    token 'ing'
  end


  def verbium
    comparison||verb and adverb # be||have||
  end

  def the_noun_that
    the?
    n=noun
    raise_not_matching "no noun" if not n
    star { selector }
    n
  end


  #def plural
  #  word #todo
  #end
  def classConstDefined
    begin
      c=word.capitalize
      return false unless Object.const_defined? c
    rescue NameError
      raise NotMatching.new
    end
    c=Object.const_get(c) if interpreting?
    c
  end

  def typeNameMapped
    x=typeName
    return Integer if x=="int"
    x
  end

  def typeName
    classConstDefined? || tokens(type_names)
  end


  def gerund
    #'stinking'
    match=@string.match(/^\s*(\w+)ing/)
    return false if not match
    @string=match.post_match
    pr     =tokens? prepositions # wrapped in
    endNode? if pr # silver
    @current_value=match[1]
    @current_value
  end

  def postjective # 4 squared , 'bla' inverted, buttons pushed in, mail read by James
    match=@string.match(/^\s*(\w+)ed/)
    return false if not match
    @string=match.post_match
    pr     =tokens? prepositions if not checkEndOfLine # wrapped in
    endNode? if pr and not checkEndOfLine # silver
    @current_value=match[1]
    @current_value
  end


  def self.self_modifying method
    method=='increase' || method=='decrease' || method.match(/\!$/)
  end

  #
  def self_modifying method
    EnglishParser.self_modifying method # -lol
  end

  def match_arguments(method, args0)
    method=@methods[method]
    i     =0
    params={}
    for a in method.args
      if (args0.has(a.name))
        params[a.name]=args0[a.name] # only for function context !!!
      else
        params[a.name]=args0[i] # only for function context !!!
      end
      i=i+1
    end
    return method, params
  end


  def filter liste, criterion
    return liste if not criterion
    list=eval_string(liste)
    list=get_iterator(list) if not list.is_a? Array
    if $use_tree
      method=criterion[:comparative]||criterion[:comparison]||criterion[:adjective]
      args  =criterion[:endNode]||criterion[:endNoun]||criterion[:expressions]
    else
      method=@comp||criterion
      args  =@rhs
    end
    list.select { |i|
      do_compare(i, method, args) rescue false #REPORT BUGS!!!
    }
  end

  def selectable
    must_contain 'that', 'whose', 'which'
    tokens? 'every', 'all', 'those'
    xs=resolve(true_variable?)|| endNoun
    s =maybe { selector } # rhs=xs, @lhs implicit! (BAD!)
    x =filter(xs, s) if @interpret rescue xs
    x
  end

  def range
    return false if @in_params
    must_contain 'to'
    _? 'from'
    a=number
    _ 'to'
    b=number
    a..b # (a..b).to_a
  end

  # # || endNode have adjective || endNode attribute || endNode verbTo verb #||endNode auxiliary gerundium
  def endNode
    raiseEnd
    x=any {# NODE }
      #try { plural} ||
      maybe { list } ||
          maybe { rubyThing } ||
          maybe { fileName } ||
          maybe { linuxPath } ||
          maybe { quote } || #redundant with value !
          maybe { article?; typeNameMapped } ||
          maybe { evaluate_property }||
          maybe { selectable } ||
          maybe { true_variable } ||
          maybe { article?; word } ||
          maybe { range } || # not params!
          maybe { value } ||
          maybe { token 'a' } # variable 'a' not as article DANGER!
    }

    po=maybe { postjective } # inverted
    x =do_send(x, po, nil) if po and @interpret
    x
  end


  def endNoun include=[]
    article?
    adjs=star { adjective } #  first second ... included
    obj =maybe { noun include }
    if not obj
      if adjs and adjs.join(' ').is_noun # KIND as adjective or noun??
        return adjs.join(' ')
      else
        raise NotMatching.new 'no endNoun'
      end
    end
    return obj if $use_tree # parent_node
    #return adjs.to_s+" "+obj.to_s # hmmm  hmmm   hmmm  W.T.F.!!!!!!!!!!!!!?????
    adjs=' ' + adjs.join(' ') if adjs and adjs.is_a? Array
    return obj.to_s + adjs.to_s # hmmm hmmm   hmmm  W.T.F.!!!!!!!!!!!!!????? ( == todo )
  end

  def any_ruby_line
    line   =@string
    @string=@string.gsub(/.*/, '')
    checkNewline
    line
  end

  def start_block type=nil
    if type
      xmls=_? '<'
      _ type
      _ '>' if xmls
    end
    return @OK if checkNewline
    maybe { tokens ':', 'do', '{', 'first you ', 'second you ', 'then you ', 'finally you ' }
  end


  def english_to_math s
    s.replace_numerals!
    s.gsub!(' plus ', '+')
    s.gsub!(' minus ', '-')

    s.gsub!(/(\d+) multiply (\d+)/, "\\1 * \\2")
    s.gsub!(/multiply (\d+) with (\d+)/, "\\1 * \\2")
    s.gsub!(/multiply (\d+) by (\d+)/, "\\1 * \\2")
    s.gsub!(/multiply (\d+) and (\d+)/, "\\1 * \\2")
    s.gsub!(/divide (\d+) with (\d+)/, "\\1 / \\2")
    s.gsub!(/divide (\d+) by (\d+)/, "\\1 / \\2")
    s.gsub!(/divide (\d+) and (\d+)/, "\\1 / \\2")
    s.gsub!(' multiplied by ', '*')
    s.gsub!(' times ', '*')
    s.gsub!(' divided by ', '/')
    s.gsub!(' divided ', '/')
    s.gsub!(' with ', '*')
    s.gsub!(' by ', '*')
    s.gsub!(' and ', '+')
    s.gsub!(' multiply ', '*')
    return s
  end

  def evaluate_index
    should_not_start_with '['
    must_contain '[', ']'
    v=endNode # true_variable
    _ '['
    i=endNode
    _ ']'
    set    =_? '='
    set    =expressions if set
    # @result=v.send :index,i if check_interpret
    # @result=do_send v,:[], i  if check_interpret
    # @result=do_send(v,:[]=, [i, set]) if set and check_interpret
    va     =resolve(v)
    @result=va.send :[], i if interpreting? #old value
    @result=va.send :[]=, i, set if set and interpreting?
    v.value=va if set and v.is_a? Variable

    # @result=do_evaluate "#{v}[#{i}]" if check_interpret
    @result
  end

  def evaluate_property
    _? 'all' # list properties (all files in x)
    must_contain_before '(', ['of', 'in', '.']
    raiseNewline
    x=endNoun type_keywords
    __ 'of', 'in'
    y=expressions
    return @result=try_evaluate_property(x, y) if @interpret
    return parent_node
  end

  #  those attributes. hacky? do better / don't use
  def subnode attributes={}
    return if not $use_tree
    return if not @current_node #raise!
    attributes.each do |name, value|
      node=TreeNode.new(name: name, value: value)
      @nodes<<node
      @current_node.nodes<<node
      @current_value=value
    end
    return attributes #@current_value
  end

  def evaluate
    __ 'what is', 'evaluate', 'how much', 'what are', 'calculate', 'eval'
    no_rollback!
    the_expression= rest_of_line
    subnode statement: the_expression
    return do_evaluate the_expression if interpreting?
    return the_expression
  end

  def newline?
    maybe { newline }
  end

  def raiseNewline
    raise EndOfLine.new if @string.blank?
  end

  def checkNewline
    comment if not @string.blank?
    if @string.blank? or @string.strip.blank?
      @line_number =@line_number+1 if @line_number<@lines.count
      if @line_number>=@lines.count #!
        @original_string=''
        @string         ='' #done!
        return @NEWLINE
      end
      #raise EndOfDocument.new if @line_number==@lines.count
      @string         =@lines[@line_number].strip #LOOSE INDENT HERE!!!
      @string         =@string.gsub(/\/\/.*/, "") # todo : Grab comment
      @original_string=@string||''
      checkNewline
      return @NEWLINE
    end
  end

  def newline_tokens
    ["\.\n", "\. ", "\n", "\r\n", ';'] #,'\.\.\.' ,'end','done' NO!! OPTIONAL!
  end

  def newline
    return @NEWLINE if checkNewline==@NEWLINE
    found=tokens newline_tokens
    return @NEWLINE if checkNewline==@NEWLINE # get new line
    return found
  end

  def newlines
    #one_or_more{newline}
    star { newline }
  end

  def NL
    tokens '\n', '\r'
  end


  def NLs
    tokens '\n', '\r'
  end


  def rest_of_statement
    @current_value=@string.match(/(.*?)([\r\n;]|done)/)[1].strip
    @string       =@string[@current_value.length..-1]
    return @current_value
  end

  # todo merge ^> :
  def rest_of_line
    if not @string.match(/(.*?)[;\n]/)
      @current_value=@string
      @string       =nil
      return @current_value
    end
    match         =@string.match(/(.*?)([;\n].*)/) # Need to preserve ;\n Characters for 'end of statement'
    @current_value=match[1]
    @string       =match[2]
    @current_value.strip!
    return @current_value
  end

  def comment_block
    token '/*'
    while not @string.match /\*\//
      rest_of_line
      newline? #weg?
    end
    @string.gsub('.*?\*\/', '')
    #token '*/'
    # add_tree_node
  end

  def comment
    raiseEnd if @string==nil
    @string.gsub!(/ -- .*/, '');
    @string.gsub!(/\/\/.*/, ''); # todo
    @string.gsub!(/#.*/, '');
    checkNewline if @string.blank?
  end

  def svg x
    @svg<<x
  end


# def variables
#   @variables
# end
#
# def result
#   @result
# end
end

