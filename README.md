# Amazon Integration

## Overview

This is a fully hosted and supported integration for use with the [Wombat](http://wombat.co) product. With this integration you can perform the following functions:

To debug feeds you can view results with the scratchpad:
[https://mws.amazonservices.com/scratchpad/index.html](https://mws.amazonservices.com/scratchpad/index.html)

### Return Orders

* Receives an amazon:order:poll message and looks for new orders in Amazon
* Returns orders to be imported into Spree

### Return Specific Order

* Receives an amazon:import:by_number message and looks for a specific order in Amazon
* Returns a specific order from Amazon filtered by `amazon_order_id` to be imported into Spree

## Connection Parameters

The following parameters must be setup within [Wombat](http://wombat.co):

| Name | Value |
| :----| :-----|
| merchant_id | Merchant ID (required) |
| marketplace_id | Marketplace ID (required) |
| access_key | Access Key (required) |
| secret_key | Secret Key (required) |

## Webhooks

The following webhooks are implemented:

| Name | Description |
| :----| :-----------|
| | |

## Wombat

[Wombat](http://wombat.co) allows you to connect to your own custom integrations.  Feel free to modify the source code and host your own version of the integration - or beter yet, help to make the official integration better by submitting a pull request!

![Wombat Logo](http://spreecommerce.com/images/wombat_logo.png)

This integration is 100% open source an licensed under the terms of the New BSD License.
