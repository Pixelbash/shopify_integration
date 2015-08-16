require "sinatra"
require "endpoint_base"

require_all 'lib'

class ShopifyIntegration < EndpointBase::Sinatra::Base
  post '/*_shipment' do # /add_shipment or /update_shipment
    summary = Shopify::Shipment.new(@payload['shipment'], @config).ship!

    result 200, summary
  end

  ## Multistep support endpoints:
  ## get_ for products, customers
  post '/multistep/*_*' do |action, obj_name|
    shopify_action_multistep "#{action}_#{obj_name}", obj_name.singularize
  end

  ## Supported endpoints:
  ## get_ for orders, products, inventories, shipments, customers
  ## add_ for product, customer
  ## update_ for product, customer
  ## set_inventory
  post '/*_*' do |action, obj_name|
    shopify_action "#{action}_#{obj_name}", obj_name.singularize
  end

  private
    def shopify_action_multistep action, obj_name
      begin
        action_type = action.split('_')[0]

        # log = Logger.new(STDOUT)
        # log.level = Logger::WARN

        shopify  = ShopifyAPI.new(@payload, @config)
        response = shopify.send(action + '_multistep')

        case action_type
        when 'get'
          response['objects'].each do |obj|
            ## Check if object has a metafield with a Wombat ID in it,
            ## if so change object ID to that prior to adding to Wombat
            wombat_id = shopify.wombat_id_metafield obj_name, obj['shopify_id']
            unless wombat_id.nil?
              obj['id'] = wombat_id
            end

            ## Add object to Wombat
            add_object obj_name, obj
          end
        end

        # avoids "Successfully retrieved 0 products from Shopify."
        if skip_summary?(response, action_type)
          return result 200
        # batches results so we don't overwhelm wombat
        elsif has_next_page?(response, action_type)
          # log.error "Returning 206"
          # log.error "Returning next page:" + response['next_page'].to_s
          add_parameter 'since', @config['since']
          add_parameter 'next_page', response['next_page']
          return result 206, response['message']
        # Last one
        else
          # log.error "Returning 200"
          add_parameter 'since', Time.now.utc.iso8601
          return result 200, response['message']
        end
      rescue => e
        print e.cause
        print e.backtrace.join("\n")
        result 500, (e.try(:response) ? e.response : e.message)
      end
    end


    def shopify_action action, obj_name
      begin
        action_type = action.split('_')[0]

        ## Add and update shouldn't come with a shopify_id, therefore when
        ## they do, it indicates Wombat resending an object.
        if wombat_resend_add?(action_type, obj_name) ||
             update_without_shopify_id?(action_type, obj_name)
           return result 200
        end

        shopify = ShopifyAPI.new(@payload, @config)
        response  = shopify.send(action)

        case action_type
        when 'get'
          response['objects'].each do |obj|
            ## Check if object has a metafield with a Wombat ID in it,
            ## if so change object ID to that prior to adding to Wombat
            wombat_id = shopify.wombat_id_metafield obj_name, obj['shopify_id']
            unless wombat_id.nil?
              obj['id'] = wombat_id
            end

            ## Add object to Wombat
            add_object obj_name, obj
          end
          add_parameter 'since', Time.now.utc.iso8601

        when 'add'
          ## This will do a partial update in Wombat, only the new key
          ## shopify_id will be added, everything else will be the same
          add_object obj_name,
                     { 'id' => @payload[obj_name]['id'],
                       'shopify_id' => response['objects'][obj_name]['id'].to_s }

          ## Add metafield to track Wombat ID
          shopify.add_metafield obj_name,
                                response['objects'][obj_name]['id'].to_s,
                                @payload[obj_name]['id']
          end

        if response.has_key?('additional_objs') &&
           response.has_key?('additional_objs_name')
          response['additional_objs'].each do |obj|
            add_object response['additional_objs_name'], obj
          end
        end

        # batches results so we don't overwhelm wombat
        if skip_summary?(response, action_type)
          return result 200
        else
          return result 200, response['message']
        end
      rescue => e
        print e.cause
        print e.backtrace.join("\n")
        result 500, (e.try(:response) ? e.response : e.message)
      end
    end

    def wombat_resend_add?(action_type, obj_name)
      action_type == 'add' && !@payload[obj_name]['shopify_id'].nil?
    end

    def update_without_shopify_id?(action_type, obj_name)
      action_type == 'update' && @payload[obj_name]['shopify_id'].nil? && obj_name != "shipment"
    end

    def has_next_page?(response, action_type)
      !response['next_page'].nil?
    end

    def skip_summary?(response, action_type)
      response['message'].nil? || get_without_objects?(response, action_type)
    end

    def get_without_objects?(response, action_type)
      action_type == 'get' && response['objects'].to_a.size == 0
    end
end
