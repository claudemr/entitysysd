# EntitySysD API documentation generation

Steps to upgrade doc generation.

Prerequisites:
* Clone ddox at the same directory level as your entitysysd work directory level `git clone git@github.com:rejectedsoftware/ddox.git`.
* Clone entitysysd doc branch at the same directory level as your entitysysd work directory level `git clone git@github.com:claudemr/entitysysd.git entitysysd_doc` and `git checkout gh-pages`.
* So you should have "entitysysd", "entitysysd_doc" and "ddox" at the same directory level.

Upgrade:
* Make sure ddox version is the last: `cd ddox ; git pull`.
* Build ddox: `dub`.
* Update public files from ddox to entitysysd: ``meld ./public ../entitysysd/doc/public``.
* Generate EntitySysD API documentation: ``cd ../entitysysd ; make clean ; make doc``.
* Update gh-pages branch from entitysysd directory to entitysysd_doc directory: ``meld ./doc/public ../entitysysd_doc``
* Commit and push modifications from both entitysysd and entitysysd_doc.
