<%--
  ~ Copyright (c) 2019, WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
  ~
  ~ WSO2 Inc. licenses this file to you under the Apache License,
  ~ Version 2.0 (the "License"); you may not use this file except
  ~ in compliance with the License.
  ~ You may obtain a copy of the License at
  ~
  ~    http://www.apache.org/licenses/LICENSE-2.0
  ~
  ~ Unless required by applicable law or agreed to in writing,
  ~ software distributed under the License is distributed on an
  ~ "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  ~ KIND, either express or implied.  See the License for the
  ~ specific language governing permissions and limitations
  ~ under the License.
--%>

<%@ page import="java.util.ResourceBundle" %>
<%@ page import="java.util.Locale" %>
<%@ page import="javax.servlet.http.Cookie" %>
<%@ page import="org.apache.commons.lang.StringUtils" %>
<%@ page import="org.wso2.carbon.identity.application.authentication.endpoint.util.AuthenticationEndpointUtil" %>
<%@ page import="org.wso2.carbon.identity.application.authentication.endpoint.util.EncodedControl" %>
<%@ page import="java.nio.charset.StandardCharsets" %>
<%@ page contentType="text/html; charset=UTF-8" %>
<%
    String BUNDLE = "org.wso2.carbon.identity.application.authentication.endpoint.i18n.Resources";

    String selectedLang = request.getParameter("ui_locales");
    if (StringUtils.isBlank(selectedLang)) {
        selectedLang = request.getParameter("locale");
    }
    if (StringUtils.isBlank(selectedLang)) {
        selectedLang = request.getParameter("lang");
    }

    if (StringUtils.isBlank(selectedLang) && request.getCookies() != null) {
        for (Cookie c : request.getCookies()) {
            if ("app_lang".equals(c.getName()) || "ui_locales".equals(c.getName()) || "language".equals(c.getName())) {
                selectedLang = c.getValue();
                break;
            }
        }
    }

    Locale effectiveLocale = null;
    if (StringUtils.isNotBlank(selectedLang)) {
        selectedLang = selectedLang.trim().toLowerCase();
        if (selectedLang.contains("fa") || selectedLang.contains("persian") || selectedLang.contains("farsi")) {
            effectiveLocale = new Locale("fa");
        } else if (selectedLang.contains("en")) {
            effectiveLocale = Locale.ENGLISH;
        } else {
            effectiveLocale = new Locale(selectedLang.split("[-_ ]")[0]);
        }
    } else if (request.getLocale() != null && "fa".equalsIgnoreCase(request.getLocale().getLanguage())) {
        effectiveLocale = new Locale("fa");
    } else {
        effectiveLocale = request.getLocale() != null ? request.getLocale() : Locale.ENGLISH;
    }

    boolean isRTL = "fa".equalsIgnoreCase(effectiveLocale.getLanguage());
    request.setAttribute("isRTL", isRTL);
    request.setAttribute("langCode", isRTL ? "fa" : "en");

    ResourceBundle resourceBundle = null;
    try {
        resourceBundle = ResourceBundle.getBundle(BUNDLE, effectiveLocale, new EncodedControl(StandardCharsets.UTF_8.toString()));
    } catch (Exception e) {
        resourceBundle = ResourceBundle.getBundle(BUNDLE, Locale.ENGLISH, new EncodedControl(StandardCharsets.UTF_8.toString()));
    }
%>
