GECOS Active Directory Sync
===========================

## Importer

##### Ruby version
Importer code works on ruby 2.x

##### Installation
Just run "bundle" inside importer directory, all dependencies will be installed

##### Configuration
you should configure the next variables in the top of the file mongo2ldap.rb to get working the importer.

``` mongo_id_root ``` the ID, in String mode, of the domain in mongo you want import into ldap, its should be something like 54887421e138230df51e66c1

``` mongo_host ```  The MongoDB host IP/DNS 

``` mongo_db ```  The MongoDB Database

``` mongo_port ``` The Mongo Port

``` data_types ``` its must be and array with the data types you want import in ldap, something like  ['ou', 'user','computer','group','storage','repository', 'repository']

``` ldap_host ``` The LDAP/AD host, like "dominio.junta-andalucia.es"

``` ldap_port ``` The LDAP/AD port, by default 389

``` ldap_auth ``` The LDAP/AD auth, like admin@junta-andalucia.es

``` ldap_pw ``` The LDAP/AD password

``` ldap_treebase ``` The base of the tree in ldap to start importing data, like "dc=domain,dc=junta-andalucia  dc=es"



Copyright
================

Copyright © 2013 Junta de Andalucia < http://www.juntadeandalucia.es >
Licensed under the EUPL V.1.1

The license text is available at http://www.osor.eu/eupl and the attached PDF
