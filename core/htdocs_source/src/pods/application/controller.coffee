`import Em from "vendor/ember"`

Controller = Em.ArrayController.extend
    needs: ["openxpki"]
    user: Em.computed.alias "controllers.openxpki.model.user"

`export default Controller`
