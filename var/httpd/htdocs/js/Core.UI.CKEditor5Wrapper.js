// --
// Copyright (C) 2010-2025 OFORK, https://o-fork.de
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

import * as CKEditor5 from 'ckeditor5';

window.Core = window.Core || {};
window.Core.UI = window.Core.UI || {};

window.OForkCKEditor5 = CKEditor5;

window.Core.UI.CKEditor5Wrapper = (function (TargetNS) {
    "use strict";

    TargetNS.GetModule = function () {
        return Promise.resolve(CKEditor5);
    };

    TargetNS.Get = function (Name) {
        if (!Name) {
            return;
        }

        return CKEditor5[Name];
    };

    TargetNS.IsLoaded = function () {
        return true;
    };

    return TargetNS;
}(window.Core.UI.CKEditor5Wrapper || {}));