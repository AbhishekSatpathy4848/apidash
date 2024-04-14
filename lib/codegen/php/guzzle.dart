import 'package:jinja/jinja.dart' as jj;
import 'package:apidash/utils/utils.dart'
    show requestModelToHARJsonRequest, stripUrlParams;
import 'package:apidash/models/models.dart' show RequestModel;
import 'package:apidash/consts.dart';

class PhpGuzzleCodeGen {
  String kStringImportNode = """<?php
require_once 'vendor/autoload.php';

use GuzzleHttp\\Client;
use GuzzleHttp\\Psr7\\Request;
{% if hasFormData %}use GuzzleHttp\\Psr7\\MultipartStream;{% endif %}


""";

  String kMultiPartBodyTemplate = """
\$multipart = new MultipartStream([
{{fields_list}}
]);


""";

  String kTemplateParams = """
\$queryParams = [
{{params}}
];
\$queryParamsStr = '?' . http_build_query(\$queryParams);


""";

  String kTemplateHeader = """
\$headers = [
{{headers}}
];


""";

  String kTemplateBody = """
\$body = {{body}};


""";

  String kStringRequest = r"""
$client = new Client();

$request = new Request('{{method}}', '{{url}}'{{queryParams}} {{headers}} {{body}});
$res = $client->sendAsync($request)->wait();

echo $res->getStatusCode() . "\n";
echo $res->getBody();

""";

  String? getCode(RequestModel requestModel) {
    try {
      jj.Template kNodejsImportTemplate = jj.Template(kStringImportNode);
      String importsData = kNodejsImportTemplate.render({
        "hasFormData": requestModel.hasFormData,
      });

      String result = importsData;

      if (requestModel.hasFormData && requestModel.formDataMapList.isNotEmpty) {
        var templateMultiPartBody = jj.Template(kMultiPartBodyTemplate);
        var renderedMultiPartBody = templateMultiPartBody.render({
          "fields_list": requestModel.formDataMapList.map((field) {
            return '''
    [
        'name'     => '${field['name']}',
        'contents' => '${field['value']}'
    ],\n''';
          }).join(),
        });
        result += renderedMultiPartBody;
      }

      var harJson =
          requestModelToHARJsonRequest(requestModel, useEnabled: true);

      var params = harJson["queryString"];
      if (params.isNotEmpty) {
        var templateParams = jj.Template(kTemplateParams);
        var m = {};
        for (var i in params) {
          m[i["name"]] = i["value"];
        }
        var jsonString = '';
        m.forEach((key, value) {
          jsonString += "'$key' => '$value',\n";
        });
        jsonString = jsonString.substring(0, jsonString.length - 2);
        result += templateParams.render({
          "params": jsonString,
        });
      }

      var headers = harJson["headers"];
      if (headers.isNotEmpty || requestModel.hasFormData) {
        var templateHeader = jj.Template(kTemplateHeader);
        var m = {};
        for (var i in headers) {
          m[i["name"]] = i["value"];
        }
        var headersString = '';
        var contentTypeAdded = false;

        m.forEach((key, value) {
          if (key == 'Content-Type' && value.contains('multipart/form-data')) {
            contentTypeAdded = false;
          } else {
            headersString += "'$key' => '$value',\n";
          }
        });

        if (requestModel.hasFormData && !contentTypeAdded) {
          headersString +=
              "'Content-Type' => 'multipart/form-data; boundary=' . \$multipart->getBoundary(), \n";
        }
        headersString = headersString.substring(0, headersString.length - 2);
        result += templateHeader.render({
          "headers": headersString,
        });
      }

      var templateBody = jj.Template(kTemplateBody);

      if (harJson["postData"]?["text"] != null) {
        result += templateBody
            .render({"body": kEncoder.convert(harJson["postData"]["text"])});
      }

      String getRequestBody(Map harJson) {
        if (harJson.containsKey("postData")) {
          var postData = harJson["postData"];
          if (postData.containsKey("mimeType")) {
            var mimeType = postData["mimeType"];
            if (mimeType == "text/plain" || mimeType == "application/json") {
              return " \$body";
            } else if (mimeType.contains("multipart/form-data")) {
              return " \$multipart";
            }
          }
        }
        return "";
      }

      var templateRequest = jj.Template(kStringRequest);
      result += templateRequest.render({
        "url": stripUrlParams(requestModel.url),
        "method": harJson["method"].toLowerCase(),
        "queryParams":
            harJson["queryString"].isNotEmpty ? ". \$queryParamsStr" : "",
        "headers": harJson["headers"].isNotEmpty ? ", \$headers," : "",
        "body": getRequestBody(harJson),
      });

      return result;
    } catch (e) {
      return null;
    }
  }
}
