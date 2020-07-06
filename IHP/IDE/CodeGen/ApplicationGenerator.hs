module IHP.IDE.CodeGen.ApplicationGenerator (buildPlan) where

import IHP.Prelude
import IHP.HaskellSupport
import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import IHP.ViewSupport
import qualified System.Process as Process
import IHP.IDE.CodeGen.Types
import qualified IHP.IDE.SchemaDesigner.Parser as SchemaDesigner
import IHP.IDE.SchemaDesigner.Types
import qualified Text.Countable as Countable
import qualified Data.Text as Text
import qualified Data.Text.IO as Text

buildPlan :: Text -> IO (Either Text [GeneratorAction])
buildPlan applicationName =
    if (null applicationName)
        then pure $ Left "Application name and controller name cannot be empty"
        else do 
            let applicationName = ucfirst applicationName
            updateRootFrontController "Main.hs" applicationName
            pure $ Right $ generateGenericApplication applicationName

generateGenericApplication :: Text -> [GeneratorAction]
generateGenericApplication applicationName = 
        let 
            typesHs = 
                "module " <> applicationName <> ".Types where\n"
                <> "import IHP.Prelude\n"
                <> "import qualified IHP.Controller.Session\n"
                <> "import qualified IHP.ControllerSupport as ControllerSupport\n"
                <> "import IHP.ModelSupport\n"
                <> "import Application.Helper.Controller\n"
                <> "import IHP.ViewSupport\n"
                <> "import Generated.Types\n\n"
                <> "data " <> applicationName <> "Application = " <> applicationName <> "Application deriving (Eq, Show)\n\n"
                <> "data ViewContext = ViewContext\n"
                <> "    { requestContext :: ControllerSupport.RequestContext\n"
                <> "    , flashMessages :: [IHP.Controller.Session.FlashMessage]\n"
                <> "    , controllerContext :: ControllerSupport.ControllerContext\n"
                <> "    , layout :: Layout\n"
                <> "    }\n"
            routesHs =
                "module " <> applicationName <> ".Routes where\n"
                <> "import IHP.RouterPrelude\n"
                <> "import Generated.Types\n"
                <> "import " <> applicationName <> ".Types\n\n"
                <> "-- Generator Marker\n"
            frontControllerHs =
                "module " <> applicationName <> ".FrontController where\n"
                <> "import IHP.RouterPrelude\n"
                <> "import IHP.ControllerSupport\n"
                <> "import Generated.Types\n"
                <> "import " <> applicationName <> ".Types\n\n"
                <> "-- Controller Imports\n"
                <> "import IHP.Welcome.Controller\n\n"
                <> "instance FrontController " <> applicationName <> "Application where\n"
                <> "    controllers = \n"
                <> "        [ startPage WelcomeAction\n"
                <> "        -- Generator Marker\n"
                <> "        ]\n\n"
                <> "instance InitControllerContext " <> applicationName <> "Application\n"
            controllerPreludeHs = 
                "module " <> applicationName <> ".Controller.Prelude\n"
                <> "( module " <> applicationName <> ".Types\n"
                <> ", module Application.Helper.Controller\n"
                <> ", module IHP.ControllerPrelude\n"
                <> ", module Generated.Types\n"
                <> ")\n"
                <> "where\n\n"
                <> "import " <> applicationName <> ".Types\n"
                <> "import Application.Helper.Controller\n"
                <> "import IHP.ControllerPrelude\n"
                <> "import Generated.Types\n"           

            viewContextHs = 
                "module " <> applicationName <> ".View.Context where\n\n"
                <> "import IHP.Prelude\n"
                <> "import qualified IHP.Controller.Session\n"
                <> "import IHP.ControllerSupport  (RequestContext (RequestContext))\n"
                <> "import qualified IHP.ControllerSupport\n"
                <> "import IHP.ModelSupport\n"
                <> "import Application.Helper.Controller\n"
                <> "import Generated.Types\n"
                <> "import qualified IHP.ViewSupport as ViewSupport\n"
                <> "import " <> applicationName <> ".View.Layout\n"
                <> "import " <> applicationName <> ".Types\n\n"
                <> "instance ViewSupport.CreateViewContext ViewContext where\n"
                <> "    type ViewApp ViewContext = " <> applicationName <> "Application\n"
                <> "    createViewContext = do\n"
                <> "        flashMessages <- IHP.Controller.Session.getAndClearFlashMessages\n"
                <> "        let viewContext = ViewContext {\n"
                <> "                requestContext = ?requestContext,\n"
                <> "                -- user = currentUserOrNothing,\n"
                <> "                flashMessages,\n"
                <> "                controllerContext = ?controllerContext,\n"
                <> "                layout = let ?viewContext = viewContext in defaultLayout\n"
                <> "            }\n"
                <> "        pure viewContext\n"

            viewLayoutHs =
                "module " <> applicationName <> ".View.Layout (defaultLayout, Html) where\n"
                <> "\n"
                <> "import IHP.ViewPrelude\n"
                <> "import IHP.Environment\n"
                <> "import qualified Text.Blaze.Html5            as H\n"
                <> "import qualified Text.Blaze.Html5.Attributes as A\n"
                <> "import " <> applicationName <> ".Types\n"
                <> "import " <> applicationName <> ".Routes\n"
                <> "import qualified IHP.FrameworkConfig as FrameworkConfig\n"
                <> "import Config ()\n"
                <> "\n"
                <> "type Html = HtmlWithContext ViewContext\n"
                <> "\n"
                <> "defaultLayout :: Html -> Html\n"
                <> "defaultLayout inner = H.docTypeHtml ! A.lang \"en\" $ [hsx|\n"
                <> "<head>\n"
                <> "    {metaTags}\n"
                <> "\n"
                <> "    <link rel=\"stylesheet\" href=\"/vendor/bootstrap.min.css\"/>\n"
                <> "    <link rel=\"stylesheet\" href=\"/app.css\"/>\n"
                <> "\n"
                <> "    {scripts}\n"
                <> "\n"
                <> "    <title>App</title>\n"
                <> "</head>\n"
                <> "<body>\n"
                <> "    <div class=\"container mt-4\">\n"
                <> "        {renderFlashMessages}\n"
                <> "        {inner}\n"
                <> "    </div>\n"
                <> "</body>\n"
                <> "|]\n"
                <> "\n"
                <> "scripts = do\n"
                <> "    when (isDevelopment FrameworkConfig.environment) [hsx|<script id=\"livereload-script\" src=\"/livereload.js\"></script>|]\n"
                <> "    [hsx|\n"
                <> "        <script src=\"/vendor/morphdom-umd.min.js\"></script>\n"
                <> "        <script src=\"/vendor/jquery-3.2.1.slim.min.js\"></script>\n"
                <> "        <script src=\"/vendor/timeago.js\"></script>\n"
                <> "        <script src=\"/vendor/popper.min.js\"></script>\n"
                <> "        <script src=\"/vendor/bootstrap.min.js\"></script>\n"
                <> "        <script src=\"/helpers.js\"></script>\n"
                <> "    |]\n"
                <> "    when (isProduction FrameworkConfig.environment) [hsx|\n"
                <> "            <script src=\"/vendor/turbolinks.js\"></script>\n"
                <> "            <script src=\"/vendor/morphdom-umd.min.js\"></script>\n"
                <> "            <script src=\"/vendor/turbolinksMorphdom.js\"></script>\n"
                <> "            <script src=\"/vendor/turbolinksInstantClick.js\"></script>\n"
                <> "        |]\n"
                <> "\n"
                <> "\n"
                <> "metaTags = [hsx|\n"
                <> "    <meta charset=\"utf-8\"/>\n"
                <> "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1, shrink-to-fit=no\"/>\n"
                <> "    <meta property=\"og:title\" content=\"App\"/>\n"
                <> "    <meta property=\"og:type\" content=\"website\"/>\n"
                <> "    <meta property=\"og:url\" content=\"TODO\"/>\n"
                <> "    <meta property=\"og:description\" content=\"TODO\"/>\n"
                <> "|]\n"

            viewPreludeHs = 
                "module " <> applicationName <> ".View.Prelude\n"
                <> "( module IHP.ViewPrelude\n"
                <> ", module " <> applicationName <> ".View.Layout\n"
                <> ", module Generated.Types\n"
                <> ", module " <> applicationName <> ".Types\n"
                <> ", module " <> applicationName <> ".View.Context\n"
                <> ", module Application.Helper.View\n"
                <> ") where\n"
                <> "\n"
                <> "import IHP.ViewPrelude\n"
                <> "import " <> applicationName <> ".View.Layout\n"
                <> "import Generated.Types\n"
                <> "import " <> applicationName <> ".Types\n"
                <> "import " <> applicationName <> ".Routes ()\n"
                <> "import " <> applicationName <> ".View.Context\n"
                <> "import Application.Helper.View\n"
        in
            [ EnsureDirectory { directory = applicationName }
            , EnsureDirectory { directory = applicationName <> "/Controller" }
            , EnsureDirectory { directory = applicationName <> "/View" }
            , CreateFile { filePath = applicationName <> "/Types.hs", fileContent = typesHs }
            , CreateFile { filePath = applicationName <> "/Routes.hs", fileContent = routesHs }
            , CreateFile { filePath = applicationName <> "/FrontController.hs", fileContent = frontControllerHs }
            , CreateFile { filePath = applicationName <> "/FrontController.hs", fileContent = frontControllerHs }
            , CreateFile { filePath = applicationName <> "/Controller/Prelude.hs", fileContent = controllerPreludeHs }
            , CreateFile { filePath = applicationName <> "/View/Context.hs",fileContent = viewContextHs }
            , CreateFile { filePath = applicationName <> "/View/Layout.hs", fileContent = viewLayoutHs }
            , CreateFile { filePath = applicationName <> "/View/Prelude.hs", fileContent = viewPreludeHs }
            ]

addImport :: Text -> [Text] -> IO ()
addImport file importStatements = do
    content :: Text <- Text.readFile (cs file)
    case addImport' file importStatements of
        Just newContent -> Text.writeFile (cs file) (cs newContent)
        Nothing -> putStrLn ("Could not automatically add " <> tshow importStatements <> " to " <> file)
    pure ()


updateRootFrontController :: Text -> Text -> IO ()
updateRootFrontController file applicationName = do
    content :: Text <- cs <$> Text.readFile (cs file)
    let importStatements = ["import " <> applicationName <> ".FrontController", "import " <> applicationName <> ".Types"]
    let newContent = addImport' content importStatements
            |> fromMaybe content
            |> addMountControllerStatement' applicationName
            |> fromMaybe content
    Text.writeFile (cs file) (cs newContent)


addImport' :: Text -> [Text] -> Maybe Text
addImport' file = appendLineAfter file ("import" `isPrefixOf`)

addMountControllerStatement' :: Text -> Text -> Maybe Text
addMountControllerStatement' applicationName file =
    let withMaybeMountedFrontController = appendLineAfter file ("mountFrontController" `isInfixOf`) ["        , mountFrontController " <> applicationName <> "Application"]
    in
        case withMaybeMountedFrontController of
            Just result -> Just result
            Nothing -> Just (Text.replace needle replacement file)
                where
                    needle =  "    controllers = []"
                    replacement = "    controllers = [\n            mountFrontController " <> applicationName <> "Application" <> "\n        ]"

appendLineAfter :: Text -> (Text -> Bool) -> [Text] -> Maybe Text
appendLineAfter file isRelevantLine newLines =
    let content :: [Text] = lines file
        lastImportLine = content
            |> zip [1..]
            |> filter (\(n, line) -> isRelevantLine line)
            |> lastMay
            |> fmap fst
    in fmap (\lastImportLine -> unlines $ (take lastImportLine content) <> newLines <> (drop lastImportLine content)) lastImportLine