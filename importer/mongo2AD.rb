#!/usr/bin/env ruby 

require 'net-ldap'
require 'mongo'
require 'json'
include Mongo

mongo_id_root = ''
mongo_host = 'localhost'
mongo_db = 'gecoscc'
mongo_port = '27017'
data_types = ['ou', 'user','computer','group','storage','repository','printer']
ldap_host = ''
ldap_port = '389'
ldap_auth = 'Administrator@dominio.junta-andalucia.es'
ldap_pw = 'password'
ldap_treebase = "dc=dominio,dc=junta-andalucia,dc=es"

class Gecoscc2ldap
  def initialize(mongo_id_root,mongo_host, mongo_db, mongo_port, data_types,ldap_host, ldap_port, ldap_auth, ldap_pw, ldap_treebase, id_hash={})
    @mongo_id_root = mongo_id_root
    @mongo_host = mongo_host
    @mongo_db = mongo_db
    @mongo_port = mongo_port
    @data_types = data_types
    @ldap_host = ldap_host
    @ldap_port = ldap_port
    @ldap_auth = ldap_auth
    @ldap_pw = ldap_pw
    @ldap_treebase = ldap_treebase
    @id_hash = id_hash
    @full_data = []
    mongo_conn()
  end

  def mongo_conn()
    level_root = 1
    mongo_client  = MongoClient.new(@mongo_host, @mongo_port)
    db = mongo_client.db(@mongo_db)
    coll = db.collection('nodes')
    @data_types.each do |dtype|
      data = coll.find({:$or => [{:$and => [{:type => dtype},{:path => /#{@mongo_id_root}/}]},{:_id => BSON::ObjectId.from_string(@mongo_id_root)}]}).to_a
      data.each do |v_data|
        h = v_data.to_h
        if h['_id'].to_s == @mongo_id_root
          level_root = h['path'].split(',').count()
        end
      end
      @full_data = data
      split_data(data, dtype, level_root)
    end
  end

  def convert_encoding(array_hashed)
    array_hashed.each_pair do |k,v|
      if v.class == String
        replacements = [ ['í','i'],['á','a'],['é','e'],['ó','o'],['ú','u'],['ñ','n'] ]
        replacements.each {|replacement| v.gsub!(replacement[0], replacement[1])}
      end
    end
    return array_hashed
  end

  def split_data(data, dtype, level_root)
    level = level_root
    checked = []
    while level != 0 do

      count_not_found = 1
      data.each do |v|
        array_hashed = v.to_h
        v_hashed = convert_encoding(array_hashed)
        level_count = v_hashed["path"].split(',').count()
        if (level_count >= level and v_hashed["type"] == "ou") or (level_count >= level and !checked.include?(v_hashed["_id"].to_s))
          @id_hash.merge!(v_hashed["_id"].to_s => v_hashed["name"])
          level_tree = level_count
          ldapmod(@ldap_host, @ldap_port, @ldap_auth, @ldap_pw, @ldap_treebase, v_hashed, dtype, level_tree) 
          checked << v_hashed["_id"].to_s
          count_not_found = 0
        end
      end

      if count_not_found == 1
        level = 0
      else
        level += 1
      end
    end
  end

  def ldapmod(ldap_host, ldap_port, ldap_auth, ldap_pw, ldap_treebase, data_hashed, dtype, level_tree)
    ldap = Net::LDAP.new
    ldap.host = ldap_host
    ldap.port = ldap_port
    ldap.auth(ldap_auth, ldap_pw)
    if ldap.bind
      check_ldap(ldap, ldap_treebase, data_hashed, level_tree)
    else
      puts "##### Auth ERROR #####"
    end
  end

  def build_mongo_dn(name, path, type, treebase)
    dn = treebase
    data = @full_data.to_a
    data.each do |v|
      array_hashed = v.to_h
      v_hashed = convert_encoding(array_hashed)
      if v_hashed["name"] == name and v_hashed["path"] == path
       
       array_path = v_hashed["path"].split(',')
       # removing 2 first id from path (root and main ou)
       array_path.shift(2)
       array_path.each do |id| 
       dn.insert(0, "ou=#{@id_hash[id]},")
       end
      end
    end
    if type == 'ou'
      dn.insert(0, "ou=#{name},")
    else
      dn.insert(0, "cn=#{name},")
    end
    return dn
  end

  def check_ldap(ldap, ldap_treebase, data, level_tree)
    treebase = ldap_treebase.gsub(' ','')
    check = 0

    dn = build_mongo_dn(data["name"], data["path"], data["type"], treebase)
    if data["type"] == 'ou'
      filter = Net::LDAP::Filter.eq('ou', '*')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           if data["master"] == "gecos"
             mod_ldap_data(ldap, data, treebase, dn)
             check = 1
           end
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end
    elsif data["type"] == 'user'
      filter = Net::LDAP::Filter.eq('objectclass', 'inetOrgPerson')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           mod_ldap_data(ldap, data, treebase, dn)
           check = 1
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end
    elsif data["type"] == 'computer'
      filter = Net::LDAP::Filter.eq('objectclass', 'computer')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           mod_ldap_data(ldap, data, treebase, dn)
           check = 1
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end
    elsif data["type"] == 'group'
      filter = Net::LDAP::Filter.eq('objectclass', 'group')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           mod_ldap_data(ldap, data, treebase, dn)
           check = 1
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end
    elsif data["type"] == 'storage'
      filter = Net::LDAP::Filter.eq('objectclass', 'container')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           mod_ldap_data(ldap, data, treebase, dn)
           check = 1
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end

    elsif data["type"] == 'repository'
      filter = Net::LDAP::Filter.eq('objectclass', 'container')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           mod_ldap_data(ldap, data, treebase, dn)
           check = 1
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end

    elsif data["type"] == 'printer'
      filter = Net::LDAP::Filter.eq('objectclass', 'container')
      ldap.search(:base => ldap_treebase, :filter => filter) do |ldap_object|
        level_ldap = ldap_object.dn
        level_ldap.slice!(",#{treebase}")

        if ldap_object.dn.downcase == dn.downcase
           mod_ldap_data(ldap, data, treebase, dn)
           check = 1
        end
      end
      if check == 0
        insert_ldap_data(ldap, data, treebase, dn)
      end
    end
  end

  def mod_ldap_data(ldap, data_hashed, treebase, dn)
    ldap.replace_attribute(dn, :description, data_hashed.to_json) 
  end

  def insert_ldap_data(ldap, data_hashed, treebase, dn)
    attributes = {}
    if data_hashed["type"] == 'ou'
      attributes.merge!(:description => data_hashed.to_json)
      attributes.merge!(:objectclass => ['top','organizationalunit'])
      ldap.add(:dn => dn, :attributes => attributes)
    elsif data_hashed['type'] == 'user'
      attributes.merge!(:description => data_hashed.to_json)
      attributes.merge!(:objectclass => ['inetOrgPerson','top'])
      ldap.add(:dn => dn, :attributes => attributes)
   elsif data_hashed['type'] == 'computer'
      attributes.merge!(:description => data_hashed.to_json)
      attributes.merge!(:objectclass => ['top','computer'])
      ldap.add(:dn => dn, :attributes => attributes)
   elsif data_hashed['type'] == 'group'
      attributes.merge!(:description => data_hashed.to_json)
      attributes.merge!(:objectclass => ['top','group'])
      ldap.add(:dn => dn, :attributes => attributes)
   else
      attributes.merge!(:description => data_hashed.to_json)
      attributes.merge!(:objectclass => ['top','container'])
      ldap.add(:dn => dn, :attributes => attributes)
    end
  end
end

Gecoscc2ldap.new(mongo_id_root, mongo_host, mongo_db, mongo_port, data_types, ldap_host, ldap_port, ldap_auth, ldap_pw, ldap_treebase)
