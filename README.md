# 使用 Istio 和 Keycloak 進行請求等級驗證和授權

Kubernetes 簡化了大規模容器化微服務的管理。然而，Kubernetes 的安全功能有限。應用程式安全的關鍵在於防止未經授權的存取。為了確保應用程式的安全訪問，必須使用基於標準的身分和存取管理 (IAM) 進行使用者身份驗證，例如 SAML、WS-Fed 或 OpenID Connect/OAuth2 標準。此外，還可以實施多因素身份驗證 (MFA) 作為額外的安全措施。

然而，Kubernetes 中並沒有原生的方式來實現這些安全功能。甚至像是請求級身份驗證和授權這樣關鍵的安全方面，也並非開箱即用。
 
這正是服務網格等工具能夠幫助我們的地方。從路由、流量整形、可觀察性和安全性，服務網格提供了許多實用功能，您的開發人員無需從頭開始建置即可將其新增至應用程式。您可以閱讀我們的部落格文章，詳細 [了解服務網格及其功能](https://www.infracloud.io/blogs/service-mesh-101/) 。

在本篇部落格文章中，我們將討論服務網格的兩項安全特性－請求級身分驗證和授權。本文稍後將使用 Istio 服務網格和 Keycloak 實作請求級身份驗證和授權。如果您喜歡視頻，可以觀看我們與 CNCF 合作舉辦的網路研討會，了解如何透過請求級身份驗證 [使用 Keycloak 和 Istio 保護請求安全](https://www.infracloud.io/cloud-native-talks/request-level-authentication-istio-keycloak/) 。

## 什麼是請求層級的身份驗證和授權？

大多數應用程式使用現代 Web 框架，並提供一個或多個 API 端點，以允許使用者、程式和其他應用程式存取您的應用程式。這些 API 端點提供以下功能：

- 允許您的應用程式使用者透過瀏覽器或行動應用程式存取您伺服器上的資料。
- 最終用戶和其他程式可以透過程式設計方式存取您的應用程式管理的資料。
- 啟用並管理應用程式不同服務之間的通訊。

如果未經授權的使用者存取這些 API 端點，則可能會被濫用或誤用。您的應用程式應該建立相應的機制來對最終使用者進行身份驗證和授權，並且僅允許存取經過身份驗證的請求。

驗證每個請求所攜帶的憑證的過程稱為請求級身份驗證。請求級授權是根據請求中憑證的合法性允許存取資源的過程。

最受歡迎的請求層級身份驗證和授權方法之一是 JWT（JSON Web Token）身份驗證。

## JWT（JSON Web Token）身份驗證

[JSON Web Token](https://jwt.io/introduction) (JWT) 是一種流行的開源身份驗證標準，它定義了一種以 JSON 物件形式在各方之間安全地傳輸資料的全面方法。由於各方之間共享的資訊使用強大的加密機制進行數位簽名，因此可以驗證和信任。

JSON Web Tokens（JWT）由三個部分組成：

- **標頭：** 它指定用於加密令牌內容的演算法。
- **有效載荷：** 它包含令牌安全傳輸的信息，也稱為聲明。
- **簽名：** 用於驗證有效載荷的真實性。

您可以閱讀有關 [JWT 令牌](https://jwt.io/introduction) 的更多資訊。

## Istio 和 JWT
 
[Istio](https://istio.io/latest/about/service-mesh/) 是最受歡迎且應用最廣泛的服務網格之一。它擁有眾多功能，可幫助您有效率地監控和保護服務。從安全角度來看，一項至關重要的功能是能夠驗證附加到最終用戶請求的 JWT。

在最終用戶請求到達您的應用程式之前，Istio 將：

- 驗證並確認 JWT 附加到最終用戶請求。
- 僅將經過身份驗證的請求轉發給應用程式。
- 拒絕存取未經身份驗證的請求。

This security feature of Istio is very useful in offloading authentication and authorization logic from your application code. You don’t have to worry about writing the authentication code yourself. Istio will manage the authentication part by validating the JWT token present in the request header.  
Istio 的這項安全功能對於從應用程式程式碼中卸載身份驗證和授權邏輯非常有用。您無需擔心自己編寫身份驗證程式碼。 Istio 將透過驗證請求標頭中存在的 JWT 令牌來管理身分驗證部分。

There are many authentication providers available, and you can select any one of them depending on your project’s requirements. Here are the few popular authentication providers which support JWT.  
有許多可用的身份驗證提供程序，您可以根據專案需求選擇其中任何一個。以下是一些支援 JWT 的常用身份驗證提供者。

- [Auth0](https://auth0.com/): Auth0 is the most popular and well-established authentication provider for integrating your application for authentication and authorization. Auth0 comes with a free tier as well which covers most of the things required for authentication and authorization for your application.  
	[Auth0](https://auth0.com/) ：Auth0 是最受歡迎且最成熟的身份驗證提供者，可用於整合您的應用程式進行身份驗證和授權。 Auth0 還提供免費套餐，涵蓋了應用程式身份驗證和授權所需的大部分功能。
- [Firebase Auth](https://firebase.google.com/docs/auth): Firebase Auth is another popular authentication service provider that allows you to add authentication and authorization to your application. Firebase allows you to add sign-in methods such as identity providers including Google, Facebook, email and password, and phone number.  
	[Firebase Auth](https://firebase.google.com/docs/auth) ：Firebase Auth 是另一個受歡迎的身份驗證服務供應商，可讓您為應用程式新增身分驗證和授權。 Firebase 可讓您新增登入方法，例如身分提供者（包括 Google、Facebook、電子郵件和密碼以及電話號碼）。
- [Google Auth](https://developers.google.com/identity/openid-connect/openid-connect): Google OIDC is one of the well-known authentication providers which you can use for both authentication and authorization.  
	[Google Auth](https://developers.google.com/identity/openid-connect/openid-connect) ：Google OIDC 是知名的身份驗證提供者之一，您可以使用它進行身份驗證和授權。
- [KeyCloak](https://www.keycloak.org/): Keycloak is a popular open source authentication service provider. Keycloak provides all the features that a typical authentication provider does. Setting up and using Keycloak is fairly straightforward, as we will see it in this blog post.  
	[KeyCloak](https://www.keycloak.org/) ：Keycloak 是一個受歡迎的開源身分驗證服務提供者。 Keycloak 提供了典型身分驗證服務提供者的所有功能。 Keycloak 的設定和使用非常簡單，我們將在本篇部落格文章中詳細介紹。

|  | **Open Source 開源** | **SSO Support SSO 支持** | **JWT Support JWT 支持** |
| --- | --- | --- | --- |
| Auth0 | No 不 | Yes 是的 | Yes 是的 |
| Firebase Auth Firebase 身份驗證 | No 不 | Yes 是的 | Yes 是的 |
| Google Auth Google 驗證 | No 不 | Yes 是的 | Yes 是的 |
| Keycloak | Yes 是的 | Yes 是的 | Yes 是的 |

## What is Keycloak? 什麼是 Keycloak？

[Keycloak](https://www.keycloak.org/) is an open source authentication service provider and identity and access management tool that lets you add authentication and authorization to applications. It provides all the native authentication features including user federation, SSO, OIDC, user management, and fine-grained authorization.  
[Keycloak](https://www.keycloak.org/) 是一個開源身分驗證服務提供者和身分與存取管理工具，可讓您為應用程式新增身分驗證和授權。它提供所有原生身份驗證功能，包括使用者聯合、SSO、OIDC、使用者管理和細粒度授權。

## Istio request authentication and authorizationIstio 請求認證和授權

In Istio, [RequestAuthentication](https://istio.io/latest/docs/reference/config/security/request_authentication/) is used for end-user authentication. It is a custom resource that defines methods for validating credentials attached to the requests. Istio performs request level authentication by validating JWT attached to the requests.  
在 Istio 中， [RequestAuthentication](https://istio.io/latest/docs/reference/config/security/request_authentication/) 用於最終用戶身份驗證。它是一種自訂資源，定義了用於驗證附加到請求的憑證的方法。 Istio 透過驗證附加到請求的 JWT 來執行請求層級的身份驗證。

RequestAuthentication lets us create authentication policies for workloads running in your mesh and define rules for validating JWTs. Based on the configured authentication rules, Istio will reject and accept the end user request.  
RequestAuthentication 允許我們為網格中執行的工作負載建立驗證策略，並定義用於驗證 JWT 的規則。根據配置的身份驗證規則，Istio 將拒絕或接受最終使用者請求。

Istio allows us to restrict access to application resources for authenticated requests only, so it is critical to .  
Istio允許我們僅限制經過身份驗證的請求對應用程式資源的訪問，因此至關重要。

## Implementing request level authentication and authorization using Istio and Keycloak使用 Istio 和 Keycloak 實現請求級身份驗證和授權

In the last section, we learned about what is request level authentication and authorization and how Istio supports JWT validation. Now, we will implement it using Istio and Keycloak.  
在上一節中，我們了解了什麼是請求級身份驗證和授權，以及 Istio 如何支援 JWT 驗證。現在，我們將使用 Istio 和 Keycloak 來實現它。

### Pre-Requisites 先決條件

- Kubernetes cluster: We will be using a kind cluster with MetalLB installed for the external load balancer. Read about [how to install and use metallb on a kind cluster](https://kind.sigs.k8s.io/docs/user/loadbalancer/).  
	Kubernetes 叢集：我們將使用安裝了 MetalLB 的 Kind 叢集作為外部負載平衡器。了解 [如何在 Kind 叢集上安裝和使用 MetalLB](https://kind.sigs.k8s.io/docs/user/loadbalancer/) 。
- Demo application: We will be using a [book-info application](https://github.com/infracloudio/istio-keycloak/tree/master).  
	演示應用程式：我們將使用 [書籍資訊應用程式](https://github.com/infracloudio/istio-keycloak/tree/master) 。

### Installing Istio 安裝 Istio

Installing Istio on a Kubernetes cluster is straightforward. For step-by-step instructions, you can follow the [official documentation for installing Istio](https://istio.io/latest/docs/setup/getting-started/).  
在 Kubernetes 叢集上安裝 Istio 非常簡單。有關逐步說明，您可以按照 [Istio 官方文件進行安裝](https://istio.io/latest/docs/setup/getting-started/) 。

Please follow these steps to install Istio on your cluster.  
請依照以下步驟在您的叢集上安裝 Istio。

- Download the latest version of Istio. At the time of writing this blog latest version of Istio is 1.17.2  
	下載最新版本的 Istio。在撰寫本文時，Istio 的最新版本為 1.17.2。
	```sh
	curl -L https://istio.io/downloadIstio | sh -
	```
	```sh
	sudo cp istio-1.17.2/bin/istioctl /usr/local/bin/
	```
- Install the Istio on your Kubernetes cluster using istioctl with a demo [configuration profile](https://istio.io/latest/docs/setup/additional-setup/config-profiles/).  
	使用 istioctl 和示範 [設定檔](https://istio.io/latest/docs/setup/additional-setup/config-profiles/) 在您的 Kubernetes 叢集上安裝 Istio。
	```sh
	istioctl install --set profile=demo -y
	✔ Istio core installed
	✔ Istiod installed
	✔ Ingress gateways installed
	✔ Egress gateways installed
	✔ Installation complete                                                                                                                                                                                    Making this installation the default for injection and validation.
	Thank you for installing Istio 1.17.  Please take a few minutes to tell us about your install/upgrade experience!  https://forms.gle/hMHGiwZHPU7UQRWe9
	```
	Verify Istio installation.  
	驗證 Istio 安裝。
	```sh
	istioctl verify-install
	```

Once Istio is installed and running in your cluster, you can enable automatically [injecting Istio sidecar](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) to your pods in two ways.  
一旦 Istio 安裝並運行在您的叢集中，您就可以透過兩種方式自動 [將 Istio sidecar 注入](https://istio.io/latest/docs/setup/additional-setup/sidecar-injection/) 到您的 pod 中。

1. You can enable Istio sidecar injection for the namespace by adding the label `istio-injection=enabled` to the namespace, so all pods running in that namespace will have Istio side car injected.  
	您可以透過為命名空間新增標籤 `istio-injection=enabled` 來為命名空間啟用 Istio sidecar 注入，這樣在該命名空間中執行的所有 pod 都會注入 Istio sidecar。
2. You can enable Istio sidecar injection for a particular pod by adding the label `sidecar.istio.io/inject=true` to the pod, that pod would automatically have Istio sidecar injected.  
	您可以透過在 pod 中新增標籤 `sidecar.istio.io/inject=true` 來為特定 pod 啟用 Istio sidecar 注入，該 pod 將自動注入 Istio sidecar。

### Install Demo App 安裝演示應用程式

Now install the demo book-info app. All Kubernetes manifests we are using in this blog post can be found on this [Github repo](https://github.com/infracloudio/istio-keycloak/tree/master).  
現在安裝 book-info 示範應用程式。本文中使用的所有 Kubernetes 清單都可以在這個 [Github 倉庫](https://github.com/infracloudio/istio-keycloak/tree/master) 中找到。

Clone git repo.克隆 git 倉庫。

```sh
git clone https://github.com/shehbaz-pathan/istio-keycloak.git
```

Move into the cloned git repo and install the app.  
進入克隆的 git repo 並安裝應用程式。

```sh
cd istio-keycloak
```

Install mysql database first and wait for db pod to go in running state.  
首先安裝 mysql 資料庫，等待 db pod 進入運作狀態。

```sh
kubectl apply -f app/database.yaml
kubectl get pods -w
NAME                           READY   STATUS              RESTARTS   AGE
book-info-db-598c7d9f5-m5l57   0/1     ContainerCreating   0          14s
book-info-db-598c7d9f5-m5l57   1/1     Running             0          25s
```

Once db pod is ready install the demo app.  
一旦 db pod 準備就緒，請安裝演示應用程式。

```sh
kubectl apply -f app/app.yaml
```

List the pods from the default namespace. You will find 2 containers in the app pod. It is because we have enabled auto Istio sidecar injection for app pods by setting the pod label to “sidecar.istio.io/inject: “true”, which automatically injects Istio sidecars in each pod of our book-info app.  
列出預設命名空間中的 Pod。您會在應用程式 Pod 中發現 2 個容器。這是因為我們已將 Pod 標籤設為“sidecar.istio.io/inject: “true”，從而為應用程式 Pod 啟用了 Istio Sidecar 自動注入功能，這將自動將 Istio Sidecar 注入到 book-info 應用程式的每個 Pod 中。

```sh
kubectl get pods
NAME                           READY   STATUS    RESTARTS     AGE
book-info-747f77b58-s9r88      2/2     Running   0         59s
book-info-db-598c7d9f5-m5l57   1/1     Running   0            2m39s
```

Now, we will set up an Istio gateway and virtual service to access the app. [Gateway](https://istio.io/latest/docs/reference/config/networking/gateway/) allows us to configure ingress traffic to our application from external systems and users. Plus, the Istio gateway does not include any traffic routing configuration so we have to create a [virtual service](https://istio.io/latest/docs/reference/config/networking/virtual-service/) to route traffic coming in from the Istio gateway to the backend kubernetes service.  
現在，我們將設定一個 Istio 網關和虛擬服務來存取該應用程式。 [網關](https://istio.io/latest/docs/reference/config/networking/gateway/) 允許我們配置來自外部系統和使用者到我們應用的入口流量。此外，Istio 閘道不包含任何流量路由配置，因此我們必須建立一個 [虛擬服務](https://istio.io/latest/docs/reference/config/networking/virtual-service/) ，將來自 Istio 閘道的流量路由到後端 Kubernetes 服務。

```sh
kubectl apply -f istio-manifests/ingressGateway.yaml
kubectl apply -f istio-manifests/virtualService.yaml
```

To access and verify the app, you have to first get the external IP of Istio ingress gateway.  
要存取和驗證應用程序，您必須先取得 Istio 入口網關的外部 IP。

```sh
# LB_IP=$(kubectl get svc istio-ingressgateway -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' -n istio-system)
```

List book details, it will return an empty array as there is no book added into the DB yet.  
列出書籍詳細信息，它將返回一個空數組，因為尚未將書籍添加到資料庫中。

```sh
curl -X GET -H “host: book-info.test.io” http://$LB_IP/getbooks
[ ]
```

Now, we will add a book by calling addbook endpoint.  
現在，我們將透過呼叫 addbook 端點來新增一本書。

```sh
curl -X POST -H "host: book-info.test.io" -d '{"isbn": 9781982156909, "title": "The Comedy of Errors", "synopsis": "The authoritative edition of The Comedy of Errors from The Folger Shakespeare Library, the trusted and widely used Shakespeare series for students and general readers", "authorname": "William Shakespeare", "price": 10.39}' "http://$LB_IP/addbook"
{
    "isbn": 9781982156909,
    "title": "The Comedy of Errors",
    "synopsis": "The authoritative edition of The Comedy of Errors from The Folger Shakespeare Library, the trusted and widely used Shakespeare series for students and general readers",
    "authorname": "William Shakespeare",
    "price": 10.39
}
```

Now again, we will list the books. This time you will find the book which we have added just now.  
現在我們再次列出書籍。這次您將找到我們剛剛新增的書籍。

```sh
curl -XGET -H "host: book-info.test.io" “http://$LB_IP/getbooks”
[
    {
        "isbn": 9781982156909,
        "title": "The Comedy of Errors",
        "synopsis": "The authoritative edition of The Comedy of Errors from The Folger Shakespeare Library, the trusted and widely used Shakespeare series for students and general readers",
        "authorname": "William Shakespeare",
        "price": 10.39
    }
]
```

### Setup Keycloak for JWT authentication設定 Keycloak 進行 JWT 身份驗證

For now, we can simply view and add books just by hitting the right endpoint – which means anyone can access the application and do the same – making it insecure. Hence, we need an authentication mechanism in place that will only allow authenticated requests to access this application. For that, we will be using Keycloak.  
目前，我們只需訪問正確的端點即可輕鬆查看和添加書籍——這意味著任何人都可以訪問該應用程式並執行相同的操作——這使其不安全。因此，我們需要一個身份驗證機制，只允許經過身份驗證的請求存取此應用程式。為此，我們將使用 Keycloak。

We will implement Keycloak on the Kubernetes cluster and configure it for issuing JWT tokens for authentication.  
我們將在 Kubernetes 叢集上實作 Keycloak，並對其進行配置以頒發 JWT 令牌進行身份驗證。

Installing and configuring Keycloak is fairly easy. You can follow the official documentation on [installing Keycloak on Kubernetes](https://www.keycloak.org/getting-started/getting-started-kube).  
安裝和配置 Keycloak 相當容易。您可以按照官方文件了解如何 [在 Kubernetes 上安裝 Keycloak](https://www.keycloak.org/getting-started/getting-started-kube) 。

Install Keycloak:安裝 Keycloak：

```sh
kubectl create -f https://raw.githubusercontent.com/keycloak/keycloak-quickstarts/latest/kubernetes-examples/keycloak.yaml
```

List the pods:列出 Pod：

```sh
kubectl get pods -l app=keycloak -w
NAME                       READY   STATUS              RESTARTS   AGE
keycloak-5bc5c7fbf-jjq29   0/1     ContainerCreating   0          19s
keycloak-5bc5c7fbf-jjq29   0/1     Running             0          29s
```

### Configure Keycloak 配置 Keycloak

Now, to configure the Keycloak to issue JWT tokens for authentication, we have to get the load balancer IP of the Keycloak service first.  
現在，要設定 Keycloak 以發出 JWT 令牌進行身份驗證，我們必須先取得 Keycloak 服務的負載平衡器 IP。

```sh
# kubectl get svc -l app=keycloak -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}'
```

Open your preferred browser and hit the load balancer IP with port 8080. Once the welcome page is open, click on Administration Console to open the login page. From here, you can log in with default admin credentials (Username: admin, Password: admin).  
開啟您常用的瀏覽器，存取負載平衡器 IP 位址和連接埠 8080。歡迎頁面開啟後，點選「管理控制台」開啟登入頁面。在這裡，您可以使用預設管理員憑證（使用者名稱：admin，密碼：admin）登入。

#### Create realm 創建領域

By default, Keycloak comes with the master realm, but for our use, we will create a new realm. You can follow the below steps for creating a new realm.  
預設情況下，Keycloak 會自備主域，但為了方便使用，我們將建立一個新的網域。您可以按照以下步驟建立新的網域。

- Click the word master in the top-left corner, then click Create realm.  
	點擊左上角的單字“master”，然後點擊“建立領域”。
- Enter Istio in the Realm name field.  
	在 Realm 名稱欄位中輸入 Istio。
- Click Create.按一下“建立”。

#### Create Oauth client 建立 Oauth 用戶端

- From the top-left corner, select the realm ‘Istio’ which we just created.  
	從左上角選擇我們剛剛建立的領域「Istio」。
- Click on Clients and then Create a Client.  
	按一下“客戶端”，然後“建立客戶端”。
- Select OpenID Connect as the client type and give Istio as the Client ID. Add Istio as the Name for the client and click next.  
	選擇 OpenID Connect 作為客戶端類型，並將 Istio 作為客戶端 ID。新增 Istio 作為客戶端的名稱，然後按一下「下一步」。
- On the second page, let the default setting as it is and click on next.  
	在第二頁，保持預設設置，點擊下一步。
- On the third page, similarly, don’t change the default setting and press the Save button.  
	第三頁，同樣不要更改預設設置，按下儲存按鈕。

#### Roles and user creation角色和使用者創建

We will be creating two roles: one for normal users who can only view book details and another one for admin users who can view and add books. Similarly, we will create two users, one normal user with a user role assigned and another one will be our admin user with an admin role assigned.  
我們將創建兩個角色：一個是普通用戶，只能查看圖書詳情；另一個是管理員用戶，可以查看和添加圖書。同樣，我們將創建兩個用戶：一個是普通用戶，分配了用戶角色；另一個是管理員用戶，並分配了管理員角色。

##### Create roles 創建角色

- From the left pane select the Realm roles and click on Create role. Enter the Role name as admin, and click on Create.  
	在左側窗格中選擇“領域角色”，然後按一下“建立角色”。輸入角色名稱“admin”，然後按一下“建立”。
- Similarly, create a role for a normal user as well with the Role name as the user.  
	同樣，為普通用戶創建一個角色，並將角色名稱作為用戶。

##### Create users 創建用戶

- From the left pane select the Users and click on Add User. Enter the username as book-admin. You can leave the rest of the value as it is and click on Create.  
	在左側窗格中選擇“使用者”，然後點選“新增使用者”。輸入“book-admin”作為使用者名稱。其餘值可以保留，然後點擊「建立」。
- Similarly, create another user with a username as book-user.  
	類似地，建立另一個用戶，用戶名為 book-user。

##### Set password for users為用戶設定密碼

Once both users are created, we will set passwords for them.  
一旦創建了兩個用戶，我們將為他們設定密碼。

- From the left pane select Users and click on book-admin user. From the top menu click on Credentials and click on Set password. Enter a strong password and confirm it. Turn off the Temporary and finally, click on the Save button.  
	在左側窗格中選擇“使用者”，然後點選“book-admin”使用者。在頂部選單中，點擊“憑證”，然後點擊“設定密碼”。輸入一個強密碼並確認。關閉「臨時」選項，最後點選「儲存」按鈕。
- Similarly, you can set the password for the book-user user.  
	同樣的，可以為 book-user 使用者設定密碼。

##### Role assignments 角色分配

- From the left pane select Users and click on book-admin user. From the top menu, select Role Mapping and click on Assign role. Check the admin role from the list which we have created recently and click on assign.  
	在左側窗格中選擇“使用者”，然後點選“book-admin”使用者。在頂部選單中，選擇“角色映射”，然後點擊“分配角色”。從我們最近建立的清單中勾選「管理員」角色，然後點擊「指派」。
- Similarly, you can assign a user role to a book-user user.  
	類似地，您可以為 book-user 使用者指派使用者角色。

### 取得所需的端點

我們需要一些端點來產生 JWT 令牌並進行 JWT 驗證。這些端點如下所示。
 
令牌 **產生 URL：http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/token**

令牌 **驗證 URL：http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/certs**

就這樣。我們已經成功設定了 Keycloak，用於為我們的演示應用程式實現請求等級的身份驗證和授權。

### Istio request level authentication and authorizationIstio 請求等級身份驗證和授權

我們已經運行了一個範例 book-info 應用，並配置了 Keycloak 來頒發 JWT 令牌。現在，我們可以使用 Istio 的 RequestAuthentication 和 Authorization 策略來驗證 JWT 令牌並授權存取請求。

#### Enable request authentication啟用請求身份驗證

First, we get the load balancer IP of the Keycloak service.  
首先，我們取得 Keycloak 服務的負載平衡器 IP。

```sh
Keycloak_IP=$(kubectl get svc -l app=keycloak -o=jsonpath='{.items[0].status.loadBalancer.ingress[0].ip}')

LB_IP=$(kubectl get svc istio-ingressgateway -o=jsonpath='{.status.loadBalancer.ingress[0].ip}' -n istio-system)
```

Then we will be creating a RequestAuthentication for validating JWT tokens from Keycloak. You can find all Kubernetes manifests that we are using [in this repo](https://github.com/shehbaz-pathan/istio-keycloak/tree/master/istio-manifests).  
然後，我們將建立一個 RequestAuthentication 來驗證來自 Keycloak 的 JWT 令牌。您可以 [在此 repo 中](https://github.com/shehbaz-pathan/istio-keycloak/tree/master/istio-manifests) 找到我們使用的所有 Kubernetes 清單。

Now create a RequestAuthentication for validating JWT tokens using Keycloak as the issuer.  
現在建立一個 RequestAuthentication 來使用 Keycloak 作為頒發者來驗證 JWT 令牌。

```sh
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: book-info-request-authentication
spec:
  selector:
     matchLabels:
      app: book-info
  jwtRules:
   - issuer: "http://$Keycloak_IP:8080/realms/Istio"
     jwks_Uri: "http://$Keycloak_IP:8080/realms/Istio/protocol/openid-connect/certs"
EOF
```

Now we will try to access the book-info application’s getbooks endpoint.  
現在我們將嘗試存取 book-info 應用程式的 getbooks 端點。

```sh
curl -X GET -H "host: book-info.test.io" http://book-info.172.19.0.6.nip.io/getbooks
[
    {
        "isbn": 9781982156909,
        "title": "The Comedy of Errors",
        "synopsis": "The authoritative edition of The Comedy of Errors from The Folger Shakespeare Library, the trusted and widely used Shakespeare series for students and general readers",
        "authorname": "William Shakespeare",
        "price": 10.39
    }
]
```

We are still able to access the endpoint without JWT token despite enabling request authentication for the book-info app. This is happening because we have not yet created an authorization policy to restrict access to authenticated requests only.  
儘管已為 book-info 應用程式啟用請求身份驗證，我們仍然能夠在沒有 JWT 令牌的情況下存取該端點。發生這種情況的原因是，我們尚未建立授權策略來限制僅限經過身份驗證的請求存取。

So, next, we will create an authorization policy.  
因此，接下來我們將建立一個授權策略。

```sh
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: book-info-auth
spec:
  selector:
    matchLabels:
       app: book-info
  rules:
   - from:
     - source:
         requestPrincipals: ["*"]
EOF
```

We will try accessing getbooks endpoint.  
我們將嘗試存取 getbooks 端點。

```sh
curl -X GET -H "host: book-info.test.io" http://book-info.172.19.0.6.nip.io/getbooks
RBAC: access denied
```

This time requests get denied, now only requests with valid JWT will be allowed to access the endpoints.  
這次請求被拒絕，現在只有具有有效 JWT 的請求才被允許存取端點。

Now, let’s try generating the JWT using the book-user user’s credentials by calling the token generation endpoint.  
現在，讓我們嘗試透過呼叫令牌來產生端點，使用 book-user 使用者的憑證產生 JWT。

```sh
curl -X POST -d "client_id=Istio" -d "username=book-user" -d "password=user123" -d "grant_type=password" "http://$Keycloak_IP:8080/realms/Istio/protocol/openid-connect/token"
{"access_token":"*****","expires_in":300,"refresh_expires_in":1800,"refresh_token":"*****","token_type":"Bearer","not-before-policy":0,"session_state":"382dd7d6-a440-43fc-b9f8-13f4dc84fe3f","scope":"profile email"}
```

Copy access token and use it as authorization bearer while calling getbooks endpoint.  
複製存取權杖並在呼叫 getbooks 端點時將其用作授權承載者。

```sh
curl -X GET -H "host: book-info.test.io" -H "Authorization: Bearer *****” http://book-info.172.19.0.6.nip.io/getbooks
[
    {
        "isbn": 9781982156909,
        "title": "The Comedy of Errors",
        "synopsis": "The authoritative edition of The Comedy of Errors from The Folger Shakespeare Library, the trusted and widely used Shakespeare series for students and general readers",
        "authorname": "William Shakespeare",
        "price": 10.39
    }
]
```

This time we are able to access the getbooks endpoint. Similarly, you can try generating a token for book-admin user and try accessing the getbooks endpoint.  
這次我們可以存取 getbooks 端點了。同樣，您可以嘗試為 book-admin 使用者產生一個令牌，然後嘗試存取 getbooks 端點。

Now, let’s try adding a new book using addbook endpoint.  
現在，讓我們嘗試使用 addbook 端點新增一本新書。

```sh
curl -X POST -d '{"isbn": 123456789123, "title": "Test Book 1", "synopsis": "This is test book 1", "authorname": "test-author1", "price": 10.39}' "http://book-info.172.19.0.6.nip.io/addbook"
RBAC: access denied
```

Adding a new book failed because access is denied. Now we will generate a token for book-user and try adding the book.  
由於訪問被拒絕，添加新書失敗。現在，我們將為 book-user 產生一個令牌，並嘗試新增這本書。

```sh
curl -X POST -d "client_id=Istio" -d "username=book-user" -d "password=user123" -d "grant_type=password" "http://$Keycloak_IP:8080/realms/Istio/protocol/openid-connect/token"
{"access_token":"*****","expires_in":300,"refresh_expires_in":1800,"refresh_token":"*****","token_type":"Bearer","not-before-policy":0,"session_state":"ccbf94e1-b3c1-4260-8ade-cb0d778b8235","scope":"profile email"}
```
```sh
curl -X POST -H "Authorization: Bearer *****" -d '{"isbn": 123456789123, "title": "Test Book 1", "synopsis": "This is test book 1", "authorname": "test-author1", "price": 10.39}' "http://book-info.172.19.0.6.nip.io/addbook"
{
    "isbn": 123456789123,
    "title": "Test Book 1",
    "synopsis": "This is test book 1",
    "authorname": "test-author1",
    "price": 10.39
}
```

As you can see, we are able to add books. Similarly, you can add books using a book-admin user.  
如你所見，我們可以添加書籍了。同樣，你也可以使用 book-admin 使用者來加入書籍。

#### Issue with current setup目前設定問題

In our current setup, both book-user and book-admin users are able to add books, but only book-admin should be allowed to add books. While book-user should only be allowed to view books and not be allowed to add books.  
在我們目前的設定中，book-user 和 book-admin 使用者都可以新增書籍，但只有 book-admin 可以新增書籍。而 book-user 只能查看書籍，而不能增加書籍。

We can restrict access of a particular endpoint to a particular user/role by extracting the role from raw JWT claim data and using conditions in the authorization policy. Now let’s see how we can control the finer-grained access using Istio authorization policies.  
我們可以透過從原始 JWT 聲明資料中提取角色，並在授權策略中使用條件，來限制特定端點對特定使用者/角色的存取。現在，讓我們看看如何使用 Istio 授權策略控制更細粒度的存取。

We will modify the authorization policy to allow only book-admin users to access /addbook endpoint and allow all users to access /getbooks endpoint.  
我們將修改授權策略，僅允許 book-admin 使用者存取 /addbook 端點，並允許所有使用者存取 /getbooks 端點。

```sh
kubectl apply -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: book-info-auth
spec:
  selector:
    matchLabels:
      app: book-info
  rules:
  - to:
    - operation:
       methods: ["GET"]
       paths: ["/bookdetails"]

  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["GET"]
        paths: ["/getbooks", "/getbookbytitle*"]

  - from:
    - source:
        requestPrincipals: ["*"]
    to:
    - operation:
        methods: ["POST"]
        paths: ["/addbook*"]
    when:
    - key: request.auth.claims[realm_access][roles]
      values: ["admin"]
EOF
authorizationpolicy.security.istio.io/book-info-auth configured
```

Now we will try adding a new book with a book-user user.  
現在我們將嘗試使用 book-user 使用者新增一本新書。

```sh
curl -X POST -d "client_id=Istio" -d "username=book-user" -d "password=user123" -d "grant_type=password" "http://$Keycloak_IP:8080/realms/Istio/protocol/openid-connect/token"
{"access_token":"*****","expires_in":300,"refresh_expires_in":1800,"refresh_token":"*****","token_type":"Bearer","not-before-policy":0,"session_state":"9fb6bcc9-57b9-4eda-8052-71daeb887b92","scope":"profile email"}
```
```sh
curl -X POST -H "Authorization: Bearer *****" -d '{"isbn": 123456789125, "title": "Test Book 3", "synopsis": "This is test book 3", "authorname": "test-author3", "price": 10.39}' "http://book-info.172.19.0.6.nip.io/addbook”
RBAC: access denied
```

這次我們不允許使用 book-user 新增書籍，因為我們只允許具有管理員角色的使用者新增書籍。
現在我們將檢查使用 admin-user 使用者新增一本書。

```sh
curl -X POST -d "client_id=Istio" -d "username=book-admin" -d "password=admin123" -d "grant_type=password" "http://keycloak.172.19.0.6.nip.io/realms/Istio/protocol/openid-connect/token"
{"access_token":"*****","expires_in":300,"refresh_expires_in":1800,"refresh_token":"*****","token_type":"Bearer","not-before-policy":0,"session_state":"a9d5398a-1e7d-4cbb-a4bf-8b7bdd70f75e","scope":"profile email"}
```
```sh
curl -X POST -H "Authorization: Bearer *****" -d '{"isbn": 123456789125, "title": "Test Book 3", "synopsis": "This is test book 3", "authorname": "test-author3", "price": 10.39}' "http://book-info.172.19.0.6.nip.io/addbook”
{
    "isbn": 123456789125,
    "title": "Test Book 3",
    "synopsis": "This is test book 3",
    "authorname": "test-author3",
    "price": 10.39
}
```

我們可以使用 book-admin 使用者新增書籍，因為我們只允許具有管理員角色的使用者新增書籍，並且我們已經在 Keycloak 中為 book-admin 使用者指派了管理員角色。此外，由於我們允許任何擁有有效 JWT 令牌的使用者存取 /getbooks 端點，因此這兩個使用者都可以查看書籍。

Istio 的請求身份驗證和授權功能與 Keycloak 一起為您的應用程式提供了出色的請求級別身份驗證和授權機制 - 這是原生 Kubernetes 所缺少的。

## 請求級別身份驗證和授權的最佳實踐

保護您的應用程式免受未經授權的存取是一項基本要求，但是，實現它需要付出巨大的努力。如果您打算這樣做，以下針對請求級身份驗證和授權的最佳實踐和注意事項將對您有所幫助：

- 始終使用 SSL 或 TLS 憑證保護應用程式中的端點。 TLS 透過加密傳輸中的消息來保護您的應用程序，因為只有接收者才擁有解密的金鑰。
- 選擇適合您要求的身份驗證提供程序，並始終使用帶有 OpenID Connect 的 OAuth2 進行請求級別身份驗證。
- 確保為不同的 API 端點使用不同的權限/角色。您可以在身分驗證提供者中建立一組權限和角色，並使用它們對應用程式 API 端點進行細粒度的存取控制。
- 確定何時使用請求層級的身份驗證和授權。您無需對每個請求都進行身份驗證和授權。您的應用程式可能包含一些需要公開存取的 API 端點，例如 /healthz、/ping 或 /public，因此請謹慎選擇要保護的端點。

## 總結

使用適當的身份驗證和授權機制來保護應用程式安全是一項重要任務。在應用程式開發階段，開發人員投入大量時間來建立良好的身份驗證和授權機制。然而，使用 Istio 和 Keycloak 等工具可以減輕開發人員的負擔，並且可以在基礎架構層級配置此驗證和授權機制。

在這篇文章中，我們了解了 Istio 如何使用 Keycloak 簡化請求層級的身份驗證和授權。然而，在現實世界中，情況可能會非常複雜，您的應用程式可能會在不同的叢集中運行數百個服務，並被數千甚至數百萬的用戶存取。

[參考網站](https://www.infracloud.io/blogs/request-level-authentication-authorization-istio-keycloak/)