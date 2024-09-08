#hash((custom . #hash((customDomain . #hash((domainName . "发布后自动生成测试域名")))))
      (deployType
       .
       #hash((config . #hash((rewrite . #hash((/$ . "index.html") (/*.html . "index.html"))))) (type . "static")))
      (package . #hash((artifact . "code.zip") (exclude . ("package-lock.json")) (include . ("build"))))
      (provider . #hash((name . "aliyun")))
      (service . #hash((name . "vite-design"))))
