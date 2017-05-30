require 'fedex/request/base'

module Fedex
  module Request
    class Shipment < Base
      attr_reader :response_details

      def initialize(credentials, options={})
        super
        requires!(options, :service_type)
        # Label specification is required even if we're not using it.
        @label_specification = {
          :label_format_type => 'COMMON2D',
          :image_type => 'PDF',
          :label_stock_type => 'PAPER_LETTER'
        }
        @label_specification.merge! options[:label_specification] if options[:label_specification]
        @customer_specified_detail = options[:customer_specified_detail] if options[:customer_specified_detail]
      end

      # Sends post request to Fedex web service and parse the response.
      # A label file is created with the label at the specified location.
      # The parsed Fedex response is available in #response_details
      # e.g. response_details[:completed_shipment_detail][:completed_package_details][:tracking_ids][:tracking_number]
      def process_request
        api_response = self.class.post api_url, :body => build_xml
        puts api_response if @debug
        response = parse_response(api_response)
        if success?(response)
          success_response(api_response, response)
        else
          failure_response(api_response, response)
        end
      end

      private

      # Add information for shipments
      def add_requested_shipment(xml)
        xml.RequestedShipment{
          xml.ShipTimestamp @shipping_options[:ship_timestamp] ||= Time.now.utc.iso8601(2)
          xml.DropoffType @shipping_options[:drop_off_type] ||= "REGULAR_PICKUP"
          xml.ServiceType service_type
          xml.PackagingType @shipping_options[:packaging_type] ||= "YOUR_PACKAGING"
          add_total_weight(xml) if @mps.has_key? :total_weight
          add_shipper(xml)
          add_origin(xml) if @origin
          add_recipient(xml)
          add_shipping_charges_payment(xml)
          add_special_services(xml) if @shipping_options[:return_reason] || @shipping_options[:cod] || @shipping_options[:saturday_delivery] # || ETD
          add_customs_clearance(xml) if @customs_clearance_detail
          add_custom_components(xml)
          xml.RateRequestTypes "ACCOUNT"
          add_packages(xml)
        }
      end

=begin
RequestedShippingDocumentType
 CERTIFICATE_OF_ORIGIN
 COMMERCIAL_INVOICE
 CUSTOMER_SPECIFIED_LABELS
 DANGEROUS_GOODS_SHIPPERS_DECLARATION
 EXPORT_DECLARATION
 GENERAL_AGENCY_AGREEMENT
 LABEL
 NAFTA_CERTIFICATE_OF_ORIGIN
 PRO_FORMA_INVOICE
 RETURN_INSTRUCTIONS

 DocumentType
enumeration CERTIFICATE_OF_ORIGIN
enumeration COMMERCIAL_INVOICE
enumeration ETD_LABEL
enumeration NAFTA_CERTIFICATE_OF_ORIGIN
enumeration OTHER
enumeration PRO_FORMA_INVOICE

Document Provider
 CUSTOMER
 FEDEX_CLS
 FEDEX_GTM
 OTHER

DocumentIdProducer
enumeration CUSTOMER
enumeration FEDEX_CSHP
enumeration FEDEX_GTM

=end

      # Electronic Trade Documents
      # def add_etd_detail(xml)
      #   xml.ETDDetail{
      #     xml.RequestedDocumentCopies{
      #       ['COMMERCIAL_INVOICE', 'LABEL']
      #         #xml.RequestedShippingDocumentType
      #     }
      #     # xml.Documents{
      #     #   #[]
      #     #   xml.LineNumber 1
      #     #   xml.CustomerReference "THIS_IS_TEST"
      #     #   xml.DocumentProducer "OTHER" #UploadDocumentProducerType
      #     #   xml.DocumentType "CUSTOMER" #UploadDocumentType
      #     #   xml.FileName "file_name.pdf"
      #     #   # xml.DocumentContent
      #     # }
      #     # xml.DocumentReferences{
      #     #   xml.LineNumber 1
      #     #   xml.CustomerReference "THIS_IS_TEST"
      #     #   xml.DocumentProvider "OTHER"
      #     #   xml.DocumentType "CUSTOMER"
      #     #   xml.DocumentIdProducer "CUSTOMER"
      #     # }
      #   }
      # end

      def add_total_weight(xml)
        if @mps.has_key? :total_weight
          xml.TotalWeight{
            xml.Units @mps[:total_weight][:units]
            xml.Value @mps[:total_weight][:value]
          }
        end
      end

      # Hook that can be used to add custom parts.
      def add_custom_components(xml)
        add_label_specification xml
      end

     # Add the label specification
      def add_label_specification(xml)
        xml.LabelSpecification {
          xml.LabelFormatType @label_specification[:label_format_type]
          xml.ImageType @label_specification[:image_type]
          xml.LabelStockType @label_specification[:label_stock_type]
          xml.CustomerSpecifiedDetail{ hash_to_xml(xml, @customer_specified_detail) } if @customer_specified_detail

          if @label_specification[:printed_label_origin] && @label_specification[:printed_label_origin][:address]
            xml.PrintedLabelOrigin {
              xml.Contact {
                xml.PersonName @label_specification[:printed_label_origin][:address][:name]
                xml.CompanyName @label_specification[:printed_label_origin][:address][:company]
                xml.PhoneNumber @label_specification[:printed_label_origin][:address][:phone_number]
              }
              xml.Address {
                Array(@label_specification[:printed_label_origin][:address][:address]).each do |address_line|
                  xml.StreetLines address_line
                end
                xml.City @label_specification[:printed_label_origin][:address][:city]
                xml.StateOrProvinceCode @label_specification[:printed_label_origin][:address][:state]
                xml.PostalCode @label_specification[:printed_label_origin][:address][:postal_code]
                xml.CountryCode @label_specification[:printed_label_origin][:address][:country_code]
              }
            }
          end
        }
      end

      def add_special_services(xml)
        xml.SpecialServicesRequested {
          if @shipping_options[:return_reason]
            xml.SpecialServiceTypes "RETURN_SHIPMENT"
            xml.ReturnShipmentDetail {
              xml.ReturnType "PRINT_RETURN_LABEL"
              xml.Rma {
                xml.Reason "#{@shipping_options[:return_reason]}"
              }
            }
          end
          if @shipping_options[:cod]
            xml.SpecialServiceTypes "COD"
            xml.CodDetail {
              xml.CodCollectionAmount {
                xml.Currency @shipping_options[:cod][:currency].upcase if @shipping_options[:cod][:currency]
                xml.Amount @shipping_options[:cod][:amount] if @shipping_options[:cod][:amount]
              }
              xml.CollectionType @shipping_options[:cod][:collection_type] if @shipping_options[:cod][:collection_type]
            }
          end
          if @shipping_options[:saturday_delivery]
            xml.SpecialServiceTypes "SATURDAY_DELIVERY"
          end
          # xml.ShipmentSpecialServicesRequested{
          #   xml.SpecialServiceTypes ['RETURN_SHIPMENT']
          #   xml.EtdDetail{
          #     xml.RequestedDocumentCopies{
          #       ['COMMERCIAL_INVOICE', 'LABEL']
          #         #xml.RequestedShippingDocumentType
          #     }
          #     # xml.Documents{
          #     #   #[]
          #     #   xml.LineNumber 1
          #     #   xml.CustomerReference "THIS_IS_TEST"
          #     #   xml.DocumentProducer "OTHER" #UploadDocumentProducerType
          #     #   xml.DocumentType "CUSTOMER" #UploadDocumentType
          #     #   xml.FileName "file_name.pdf"
          #     #   # xml.DocumentContent
          #     # }
          #     # xml.DocumentReferences{
          #     #   xml.LineNumber 1
          #     #   xml.CustomerReference "THIS_IS_TEST"
          #     #   xml.DocumentProvider "OTHER"
          #     #   xml.DocumentType "CUSTOMER"
          #     #   xml.DocumentIdProducer "CUSTOMER"
          #     # }
          #   }
          # }
        }
      end

      # Callback used after a failed shipment response.
      def failure_response(api_response, response)
        puts response
        error_message = if response[:process_shipment_reply]
          [response[:process_shipment_reply][:notifications]].flatten.first[:message]
        else
          "#{api_response["Fault"]["detail"]["fault"]["reason"]}\n--#{api_response["Fault"]["detail"]["fault"]["details"]["ValidationFailureDetail"]["message"].join("\n--")}"
        end rescue $1
        raise RateError, error_message
      end

      # Callback used after a successful shipment response.
      def success_response(api_response, response)
        @response_details = response[:process_shipment_reply]
      end

      # Build xml Fedex Web Service request
      def build_xml
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.ProcessShipmentRequest(:xmlns => "http://fedex.com/ws/ship/v#{service[:version]}"){
            add_web_authentication_detail(xml)
            add_client_detail(xml)
            add_version(xml)
            add_requested_shipment(xml)
          }
        end
        output = builder.doc.root.to_xml
        File.write("#{Time.now}.xml", output)
        output
      end

      def service
        { :id => 'ship', :version => Fedex::API_VERSION }
      end

      # Successful request
      def success?(response)
        response[:process_shipment_reply] &&
          %w{SUCCESS WARNING NOTE}.include?(response[:process_shipment_reply][:highest_severity])
      end

    end
  end
end
