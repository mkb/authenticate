require 'rails/generators/base'
require 'rails/generators/active_record'

module Authenticate
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include Rails::Generators::Migration
      source_root File.expand_path('../templates', __FILE__)

      def create_initializer
        copy_file 'authenticate.rb', 'config/initializers/authenticate.rb'
      end

      def inject_into_application_controller
        inject_into_class(
            "app/controllers/application_controller.rb",
            ApplicationController,
            "  include Authenticate::Controller\n"
        )
      end

      def create_or_inject_into_user_model
        if File.exist? "app/models/user.rb"
          inject_into_file(
              'app/models/user.rb',
              '  include Authenticate::User\n\n',
              after: 'class User < ActiveRecord::Base\n'
          )
        else
          copy_file 'user.rb', 'app/models/user.rb'
        end
      end

      def create_authenticate_user_migration
        if users_table_exists?
          create_add_columns_migration
        else
          create_new_users_migration
        end
      end

      def copy_migration_files
        copy_migration 'add_authenticate_brute_force_to_users.rb'
        copy_migration 'add_authenticate_timeoutable_to_users.rb'
        copy_migration 'add_authenticate_password_reset_to_users.rb'
      end

      private

      def create_new_users_migration
        config = {
            new_columns: new_columns,
            new_indexes: new_indexes
        }
        copy_migration 'create_users.rb', config
      end

      def create_add_columns_migration
        if migration_needed?
          config = {
              new_columns: new_columns,
              new_indexes: new_indexes
          }
          copy_migration('add_authenticate_to_users.rb', config)
        end
      end

      def copy_migration(migration_name, config = {})
        unless migration_exists?(migration_name)
          migration_template(
              "db/migrate/#{migration_name}",
              "db/migrate/#{migration_name}",
              config
          )
        end
      end

      def migration_needed?
        new_columns.any? || new_indexes.any?
      end

      def new_columns
        @new_columns ||= {
            email: 't.string :email',
            encrypted_password: 't.string :encrypted_password, limit: 128',
            session_token: 't.string :session_token, limit: 128',

            # trackable, lifetimed
            current_sign_in_at: 't.datetime :current_sign_in_at',
            current_sign_in_ip: 't.string :current_sign_in_ip, limit: 128',
            last_sign_in_at: 't.datetime :last_sign_in_at',
            last_sign_in_ip: 't.string :last_sign_in_ip, limit: 128',
            sign_in_count: 't.integer :sign_in_count'
        }.reject { |column| existing_users_columns.include?(column.to_s) }
      end

      def new_indexes
        @new_indexes ||= {
            index_users_on_email: 'add_index :users, :email',
            index_users_on_session_token: 'add_index :users, :session_token'
        }.reject { |index| existing_users_indexes.include?(index.to_s) }
      end

      def migration_exists?(name)
        existing_migrations.include?(name)
      end

      def existing_migrations
        @existing_migrations ||= Dir.glob("db/migrate/*.rb").map do |file|
          migration_name_without_timestamp(file)
        end
      end

      def migration_name_without_timestamp(file)
        file.sub(%r{^.*(db/migrate/)(?:\d+_)?}, '')
      end

      def users_table_exists?
        ActiveRecord::Base.connection.table_exists?(:users)
      end

      def existing_users_columns
        return [] unless users_table_exists?
        ActiveRecord::Base.connection.columns(:users).map(&:name)
      end

      def existing_users_indexes
        return [] unless users_table_exists?
        ActiveRecord::Base.connection.indexes(:users).map(&:name)
      end

      # for generating a timestamp when using `create_migration`
      def self.next_migration_number(dir)
        ActiveRecord::Generators::Base.next_migration_number(dir)
      end


    end
  end
end
