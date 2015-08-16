module Shopify
  module GetMultistep

    def get_products_multistep
      page_size = 50
      objs      = Array.new
      count     = (api_get 'products' + '/count')['count']
      pages     = (count / page_size.to_f).ceil
      next_page = (@config['next_page'].to_i || 0) + 1

      shopifys = api_get 'products', {'limit' => page_size, 'page' => next_page}
      shopify_objs = format_objs shopifys, Product

      # Now we need to page the return with 206 and 100 object limit
      results = {
        'objects' => Util.wombat_array(shopify_objs),
        'message' => "Successfully retrieved Page #{next_page} of #{pages} products from Shopify.",
      }

      if next_page < pages
        results['next_page'] = next_page
      end

      results
    end

    def get_customers_multistep
      page_size = 50
      objs      = Array.new
      count     = (api_get 'customers' + '/count')['count']
      pages     = (count / page_size.to_f).ceil
      next_page = (@config['next_page'].to_i || 0) + 1

      shopify_objs = api_get 'customers', {'limit' => page_size, 'page' => next_page}
      shopify_objs = format_objs shopify_objs, Customer

      # Now we need to page the return with 206 and 100 object limit
      results = {
        'objects' => Util.wombat_array(shopify_objs),
        'message' => "Successfully retrieved Page #{next_page} of #{pages} customers from Shopify.",
      } 

      if next_page < pages
        results['next_page'] = next_page
      end

      results
    end
  end
end

