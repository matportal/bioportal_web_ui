// Entry point for the build script in your package.json


import { Turbo } from "@hotwired/turbo-rails";
import "./controllers";
import "./component_controllers";
import "./cookie_consent";
import "./cookie_consent";

Turbo.session.drive = false;
Turbo.setConfirmMethod((message) => {
    return new Promise((resolve, reject) => {
        alertify.confirm(message, (e) => {
            resolve(e)
        })
    })
})
