DOSSIER

★English as a programming language★
-----------------------------------

A revolution will break loose. Soon every English speaker will be able to completely control their devices via voice. People will realize that by giving their devices commands, they are actually programming them. Now imagine you could not only say “remind me to take out the trash next Sunday”, but also complicated sequences like:
``
Here is what you do when I enter my office.
You switch on the coffee machine.
You request the status report from all employees who haven't submitted the status report yet.
``
< Replace this example >

While Siri is already great for retrieving information it falls a bit short in accessing some of the phones capabilities. In some of the existing [assistants](http://jeannie-assistant.com/) on android you can already say things like “enable Bluetooth, turn down the volume, open speech input settings” etc.
But this is only the first step in the evolution of speech control.

★ Voice operating systems ★
---------------------------

Next you will not only be able to control some specific apps but most applications on your device.
Ultimately a voice operating system will enable complete new workflows, from taking pictures to modifying them, to putting them into documents, to sharing them ...
 Of course this requires the operating systems to specify mechanisms in which applications can promote their capabilities. In a Narrow way this is already done with Dragon NaturallySpeaking on Windows machines, where you can access all the functionality which is accessible through the menus by speech. A broader approach will allow applications to reveal patterns , Phrases or keywords for which they can provide a useful action. Alternatively the speech input flow will be forwarded to the active application which can then decide to do something useful with it or not.

After that or maybe in parallel the really interesting change in paradigms will occur: People will not only be able to completely control everything they see on their screen by voice, but they will also be able to control the future state of their device. First by single sentences like “enable airplane mode whenever I enter an airplane”. Then by whole sequences of commands, which should be seen as programs or algorithms. Now all we needs is a –functionality complete– set of speakable structures and the fun can really begin:


★ Examples of English script  ★ 
-------------------------------
0) Simple-most examples

`Print all prime numbers that are smaller than 17`

```
To make a beep
    on apple say "beep"
	Print Character 7
Done

To say something
    bash "say" something
End
```

```
How to check if someone is online on Skype
	Call java Skype.checkStaus(Someone)
	Return yes If Result equals "online"
	Return no otherwise
Done
```

```
While Peter is online on Skype
	Make a beep
	Sleep for 10 seconds
Done
```

Advanced examples
-----------------
`Whenever I received an email, You check if it's Sender is my girlfriend.
If so, You turn the light bulb in the living room green until I clap my hand.`

* Predecessors *
----------------
[AppleScript](https://en.wikipedia.org/wiki/AppleScript) 
Despite of its many shortcomings it should be a real inspiration to anyone in the language community.
Many of the patterns in the first version of English script were heavily influenced by the grammar of AppleScript.
The main shortcomings of AppleScript are:
1) Siloed environment, not compiling to any cross-platform framework
2) Slow execution
3) Unreliable execution: Things often don't work as expected and crash without warning nor explanation 
4) Some syntactic oddities ("tell me" to call a local function, Linux paths etc)

Ideally of course we would love to solve/avoid those shortcomings in EnglishScript

In the past people came up with [crazy solutions](http://shorttalk-emacs.sourceforge.net/EmacsListen/from-listen/quickref.pdf) to cope with repetitive strain injuries! In five years, programming computers by voice will be as commonplace as dictating emails
 by voice.

Guiding principles 
------------------
The language is optimized for speakability and readability, without compromising functionality nor rigor:
Avoid special characters whenever possible
All English words which are not nouns or verbs are keywords, especially prepositions and pronouns.
Solve the block problem ruby style with end keywords: do blah done
  def done_words
    ['done','end','okay','ok','OK','O.K.','}','alright','that\'s it',..]
  end
Update: now python style dedent is accepted too

Allow optional special characters to increase readability

Design the language for brevity but still allow longer formulations
Example:
``
To beep
	Print 7

is equally syntactically correct as the following

function beep() returns void:
    print(0xa)
end beep

``
This comes without a heavy burden on the parser:
it just contains some optional character/word patterns.

* Future *
----------
Even in the beginning we are not just trying to bring AppleScript to our environments, but to have a better syntax 
and runtime from the very start.
We are also introducing new concepts and keywords 
◦ **once** / **whenever** / **as long as** / ... keywords, to connect a programming block to the event notification system.
◦ **my** Keyword to access the synchronized user graph. `search my email for spam. delete all results`
◦ Event pipeline: Listeners and triggers, “Clap my hand”, to be specified in other programming blocks.
◦ Library server: we want to make sure that a good package bundler is part of the distribution (a better gem/pip/...)
◦ AND functional snippets will be uploaded to a function server, to be [retrieved](http://crystal-lang
.org/2015/04/01/auto.html) by other user.
◦ Clarification dialogs: If one of the mentioned objects or events is unknown, the system/IDE can ask things like:
How do I know when you clap your hands
◦ API to connect with external code and existing libraries. For example you could write a little handclapping detection engine in c and then whenever a handclap occurs you invoke EnglishScript::Event("my.hand.clap") or EnglishScript::EventSPO(Me,"clap","hand")

Our engine should be smart enough to semantically match "I clap my hand" against this event.
◦ We not only have a Personal graph for the 'my/me/I' keyword but also an active graph for objects around you: 
"bulb[@living_room].color=green". The bulb object needs to have a method ‘turn green’ or 'set color'.

Event system
------------
```
once(<event>) do <block> end
once beeped do print 'yay' end
beep() -> trigger["beeped"] IFF there is a listener
whenever I clap my hand you toggle the light in the living room

to toggle the light in a room
    set room.light.on = not room.light.on
end
```

* Execution *
-------------
There are many steps to be taken! The complexity of the task demanded that we first introduced these features in an
 existing language: Ruby
Writing an interpreter for these features was relatively easy in a dynamic language like Ruby (a universell DSL if you 
will). We are currently working on writing a compiler which dumps Python bytecode, thanks to its nice AST. We 
[generalized](https://github.com/pannous/kast/) this AST a little, so that we can hopefully soon also emit bytecode for
 the JVM and DLR.


To summarize the requested runtime features:
A lightweight semantic event system, with a simple syntax to connect with listeners: 
A personnel and general object graph with attached methods.

* Difficulties *
----------------
Difficulties in first implementations of such a system

Users a.k.a. speakers of such a programming language will have the inherent problem of expecting too much.
They are very prone to forgetting that in the beginning they can only dictate a certain subset of English.
Even if the syntax is in accordance with the specific grammar, users might be disappointed that the parsed command “Find me $1 million” might not yield the results they expect.

 Some people argue that concise / mathematical languages like c will never get replaced by more verbose languages. And they are right: you probably don't want to write a kernel driver in English, for a very long time, until you have very good compilers. 
But still the use cases for English as a programming language are so incredibly huge and universal, that it might outshine old-fashioned languages quickly.


* Ambiguities *
---------------
Naturally the phenomenon of ambiguities in English will extend to all our programming language.
 clearly we need mechanisms still results those ambiguities at programming time, at compile time and at runtime.

There are several paths in which this can be achieved:
1) Get the proposed system running in Ruby as discussed earlier. Then create a parser which translates our beautiful English into hopefully not that ugly ruby/java/lisp code.
2) Create an annotation system which will resolve the issues around the text
3) Create a proper representation Language which is sufficiently beautiful and deterministic. Parse every input sentence to that representation. For portability write down the original English and the interpretation next to each other when sending the file along. Reinterpret the English sentence whenever it is changed, Maybe taking into consideration's manual modifications to the representation if they Did Oakar.
4) Ask the user to resolve this ambiguities when entering the phrase and then just compile the interpretation down to byte coat. This is the biggest disadvantage that a user might have picked the wrong resolution Blenhem Tehuti and will not see this error directly anymore.
5) Have a lightweight disambiguation inside English, on demand, through [annotations] and (through groupings):
“Time[noun] flies[verb]  (like an arrow)”
6) Have a pre-compile intermediate format, which is unambiguous, yet readable by humans and by computers, possibly Clojure?

This has the big advantage of being perfectly readable yet having the property of being parsable in a deterministic way.
Maybe operator binding can make many braces unnecessary. However it's always the task of the compiler to suggest and insert the braces. Should the system for some reason become certain about whats the disambiguation of the parsetree, it can remove the braces itself.

★ Blocks ★
----------
Here we present blocks as example for the language syntax/structure:

Just a quick reminder, this is how blocks look like in Ruby:
```
7.Times do
	prints "I am happy"
end
```

Blocks can be opened in many different ways. We want to add the following keywords or scenarios to the existing ruby blocks:
```
Once (trigger condition) do (block) end
As long as...
As soon as ...
Repeat ...	# just function, doesn't need keyword
Infinitly do ... # just function, doesn't need keyword
```
And many more.

You might have noted that some of the keywords are redundant. We believe that this is not a bad thing.
We want to give the program a bit more natural flexibility when it comes to ending blocks thus we also allow "done" "thats it" "ok" and other keywords to denote the ending of the block.

``
How to make a beep
	Print 0x0a
Done
``

Preferably long blocks can be ended by naturally annotating what the block was about:

```
how to calculate the volume of a mesh object:
	// Long calculation block goes here
done calculating the volume
```

★Gradual Typing★
----------------
(Optional typing)[https://en.wikipedia.org/wiki/Gradual_typing], merging strongly typed and dynamic languages, will be one of the killer features of angle/english-script.
One way of in Achieving this else tell compile multiple variants of one method. 

By default a dynamic method with dynamic dispatch will be compiled for every function definition
````
def myadd x,y
   x+y
   
=>   
def myadd(any x,any y) returns any
   x+y   
```

If the compiler figured out a static type pathway then a strongly typed function will be added:

``
int myadd(x:int,y:int)
	return x+y
``

Fortunately multiple method signatures are possible in the JVM and DLR, unfortunately not in Ruby or Python.
So for now this feature has to be restricted so specific runtime environments.
https://www.youtube.com/watch?v=2wDvzy6Hgxg

Note type hints can be java style or python style (with braces).
Or english style:
```
to add a number x to a number y
	return x plus y 
```

★Implementation ★
-----------------
As we pointed out there are different paths by which this language can come into existence. Therefore there are many possible different implementations. In fact what we should do first is clearly specify the syntax limitations and the desired features of our language.

One good way of doing this is through a grammar specification language/tool, for example EBNF as in ANTLR.
< Copy paste nice examples> 

We can also create syntax highlighting to distinguish the structural Keywords are patterns from free "subject predicate object method calls" like: (computer) purge trash! A Textmate bundle is in the works. 
There is a lot we can learn and from AppleScript here.
UPDATE: A Textmate bundle is ready!

★ Experience and Experiments ★
------------------------------
Update: We migrated our ANTLR experiment to a very nice [domain specific language in ruby](https://github.com/pannous/english-script/blob/master/lib/english-script/english-parser.rb).
We are thrilled by the speed of progress, by the cleanness and uniqueness of the syntax.
Sure we are currently using much black Ruby magic, but our goal is to bootstrap the system so that it can finally compile itself in its own language, similar to [kal](https://github.com/rzimmerman/kal)

★ History : ANTLR  ★
--------------------
So far we did create semantic graphs which satisfies our needs. We started to write the first Verizon of the grammar for English script. However we did run into the limitations of ANTLR. Specifically it's inability to include large sets in a natural way.
We have a list of English verbs,nouns,prepositions,etc and naturally we wanted to include them in our grammar:

To show the problem in a simplified way
``
Statement:: 'If' condition 'then' action
Action:: verb 'the' noun
``

Forget for a moment that many verbs are also nouns and vice versa, we couldn't even include a list of verbs. It is easy to create a list of 20 burps but our list of 50,000 words just made the compiler crash.
 when we started to get into the in workings of antler we soon found out that the whole system is based on a character-centric state machine instead of a word state machine. This may create Larry efficient machines for parsers of arbitrary strings sets. However in our case we have cleanly tokenized strings sets and optimizing the parser by grouping different words until little subtrees just makes the code unreadable.

To illustrate the difference:
Let's say our grammar has three different patterns:
Begin to action
Before condition action


what we want is some parser generator which creates something along the lines
Switch(firstWord)
Case begin: ...
Case before: ...

What Antlr produces is very different and horrible indeed:
Switch firstWhatever:
Case be:
 Switch nextBla
 Case gin:
 Case ore:
Case c3

 this is a good solution to a set of problems which, unfortunately, is distinct from our problem.
We didn't contact Terrence the great Mastermind behind ANTLR yet, In order to ask him what it would take to create a word centric version of antler. Our fear is that something new and clean has to be designed from the ground up. It might not be rocket science but it could be a good load of hard work, deep thinking and many sideways and mistakes involved.
That's just for the proper parser, Which ideally should be able to have semantic flow control as well, Similarily to what is already possible in antler. "Ideally" is an understatement, it will become a necessity in the process.

Roadmap
-------

Package program as a gem or similar.

Use [AST](https://en.wikipedia.org/wiki/Abstract_syntax_tree) not only for on-the-fly interpretation,
 but also for **compilation** to JVM byte code, or even native code!

``
First step: Use as an extension for JRuby.
Second step: Deploy as a standalone Java jar.
Third step: Compile to native code.
Crazy step: compile to asm.js ??
``

So far this language runs in the Ruby runtime environment (without any Java). It would be nice if we could keep it this way, even if compiling to Java byte code will become optionally possible.

★ Interesting related projects ★
--------------
http://techcrunch.com/2014/10/01/eve-raises-2-3m-to-rethink-programming/

★ Last words ★
--------------

To those naysayers saying that draping a parser or even a grammar for English is impossible:
First we don't want to parse the whole richness of English
Secondly we can assume a cooperative user so whenever the Parser is not sure what to do the user can assist
Thirdly modern C++ parsers probably have a much higher complexity of what we want to achieve

And lastly (this is only partly a joke and should illustrate some limitations of grandma theory): if we say that each statement has to be less then 100 Wurts we are not faced with a class 0 language but with a class four Grammar, namely a finite set of commands. Of course the practical truth lies in between.

★ Summary TL;DR ★
---------
In the near future a new programming language will appear which has the unique property of being speakable.
It will get rid of all those braces and brakets, and it will consistently use (English like syntax)[https://github.com/pannous/english-script/tree/master/examples].

Programming is one of the most empowering experiences you can have!
It is like writing a book that can interact with the world in many dimensions.
I want to bring the joy of writing software to everyone, including your mom.
