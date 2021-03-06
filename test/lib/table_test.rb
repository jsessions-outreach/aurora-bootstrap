require 'test_helper'

class TableTest < Minitest::Test
  def setup
    @prefix   = ENV.fetch "PREFIX", ""
    @bukkit   = ENV.fetch "EXPORT_BUCKET"

    @client   = Mysql2::Client.new( host: ENV.fetch( "DB_HOST" ),
                                username: ENV.fetch( "DB_USER" ),
                                password: ENV.fetch( "DB_PASS" ))


    @exporter = AuroraBootstrapper::Exporter.new( client: @client,
                                                  prefix: @prefix,
                                           export_bucket: @bukkit )
    @table    = AuroraBootstrapper::Table.new database_name: "master",
                                                 table_name: "users",
                                                     client: @client
  end

  def test_fields
    assert_equal [ "id", "email", "first_name", "last_name" ], @table.fields
  end

  def test_fields_row
    assert_equal "'id', 'email', 'first_name', 'last_name'", @table.fields_row
  end

  def test_export_statement
    expected = <<~SQL
      SELECT 'id', 'email', 'first_name', 'last_name'
        UNION ALL
      SELECT id, email, first_name, last_name
        FROM master.users
      INTO OUTFILE S3 's3://bukkit/master/users'
        FIELDS TERMINATED BY 'AURORA-BOOTSTRAP-EXPORT-COL-DELIMITER'
        LINES TERMINATED BY 'AURORA-BOOTSTRAP-EXPORT-ROW-DELIMITER'
        MANIFEST ON
        OVERWRITE ON
    SQL
    assert_equal expected, @table.export_statement( into_bucket: "s3://bukkit")
  end

  def test_export_logs
    with_logger PutsLogger.new do

      assert_output( /Export failed:/ ) do
        @table.export!( into_bucket: "s3://bukkit")
      end

      mock = Minitest::Mock.new
      mock.expect :export!, nil

      @client.stubs( :query ).returns( "yay" )
      
      assert_output( /Export succeeded: / ) do
        assert @table.export!( into_bucket: "s3://bukkit")
      end
    end
  end

  def test_blacklisted_fields
    table = table_with_blacklist( ["first_name", "users.last_name", "master.users.email"] )
    
    assert table.blacklisted_field?( "first_name" )
    assert table.blacklisted_field?( "last_name" )
    assert table.blacklisted_field?( "email" )
  end

  def test_blacklisted_fields_with_regexps 
    table = table_with_blacklist( ["/first.*/", "/users.last.*/", "/.*.users.email/"] )
    
    assert table.blacklisted_field?( "email" )
    assert table.blacklisted_field?( "first_name" )
    assert table.blacklisted_field?( "last_name" )    
  end

  def test_blacklisting_fields_across_tables
    blacklisted_fields = [ '/pho.*.link/', 'user_id' ]

    tables = [ AuroraBootstrapper::Table.new( database_name: "user_stuff",
                                                 table_name: "photos",
                                                     client: @client,
                                         blacklisted_fields: blacklisted_fields ),

               AuroraBootstrapper::Table.new( database_name: "user_stuff",
                                                 table_name: "websites",
                                                     client: @client,
                                         blacklisted_fields: blacklisted_fields ) ]
    assert_equal [["id"], ["id", "link"]], tables.map(&:fields)
  end

  def test_export
    # because those logs aren't actually useful
    with_nil_logger do

      AuroraBootstrapper::Table.any_instance.stubs( :export_statement ).returns( "select 'hurrah'" )

      assert @exporter.export!

    end
  end

  private

  def table_with_blacklist( blacklisted_fields )
    AuroraBootstrapper::Table.new database_name: "master",
                                     table_name: "users",
                                         client: @client,
                             blacklisted_fields: blacklisted_fields
  end
end