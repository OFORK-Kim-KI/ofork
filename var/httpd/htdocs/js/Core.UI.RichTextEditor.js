// --
// Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
// Copyright (C) 2010-2025 OFORK, https://o-fork.de
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.UI = Core.UI || {};

/**
 * @namespace Core.UI.RichTextEditor
 * @memberof Core.UI
 * @description
 *      Richtext Editor based on CKEditor 5.
 */
Core.UI.RichTextEditor = (function (TargetNS) {
    var Instances = {},
        Initializing = {},
        TimeOutRTEOnChange;

    function IsJQueryObject(Object) {
        if (typeof isJQueryObject === 'function') {
            return isJQueryObject(Object);
        }

        return Object && Object.jquery;
    }

    function GetEditorID($EditorArea) {
        var EditorID = '';

        if (IsJQueryObject($EditorArea) && $EditorArea.length === 1) {
            EditorID = $EditorArea.attr('id') || '';
        }

        if (EditorID === '') {
            Core.Exception.Throw('RichTextEditor: Need exactly one EditorArea!', 'TypeError');
        }

        return EditorID;
    }

    function CheckFormID($EditorArea) {
        return $EditorArea.closest('form').find('input:hidden[name=FormID]');
    }

    function NormalizeLanguage(Language) {
        var NormalizedLanguage = (Language || 'en').toLowerCase();

        NormalizedLanguage = NormalizedLanguage.replace(/_/g, '-');

        return NormalizedLanguage.split('-')[0] || 'en';
    }

    function GetEditorLanguage() {
        var Language = Core.Config.Get('CKEditor5Language') || Core.Config.Get('UserLanguage') || 'en';

        Language = NormalizeLanguage(Language);

        if ($.inArray(Language, ['en', 'de', 'fr', 'it']) === -1) {
            Language = 'en';
        }

        return Language;
    }

    function GetCKEditor5Module() {
        if (window.OForkCKEditor5 && window.OForkCKEditor5.ClassicEditor) {
            return Promise.resolve(window.OForkCKEditor5);
        }

        if (window.CKEDITOR && window.CKEDITOR.ClassicEditor) {
            window.OForkCKEditor5 = window.CKEDITOR;
            return Promise.resolve(window.OForkCKEditor5);
        }

        return Promise.reject(
            new Error('RichTextEditor: CKEditor 5 UMD build is not loaded.')
        );
    }

    function BuildUploadURL($EditorArea) {
        var $FormID = CheckFormID($EditorArea);

        if (!$FormID.length) {
            return '';
        }

        return Core.Config.Get('Baselink')
            + 'Action='
            + Core.Config.Get('RichText.PictureUploadAction', 'PictureUpload')
            + '&FormID='
            + encodeURIComponent($FormID.val())
            + '&'
            + encodeURIComponent(Core.Config.Get('SessionName'))
            + '='
            + encodeURIComponent(Core.Config.Get('SessionID'));
    }

    function StripEmptyContent(Data) {
        var StrippedContent = Data || '';

        StrippedContent = StrippedContent.replace(/\s+|&nbsp;|<\/?\w+[^>]*\/?>/g, '');

        return StrippedContent;
    }

    function SanitizeDataForTextarea(Data) {
        if (!Data) {
            return '';
        }

        if (StripEmptyContent(Data).length === 0 && !Data.match(/<img/i)) {
            return '';
        }

        return Data;
    }

    function GetFontSizeOptions() {
        var FontSizes = Core.Config.Get(
            'RichText.FontSizes',
            '8px;10px;12px;14px;16px;18px;20px;22px;24px;26px;28px;30px;'
        );

        return $.grep(FontSizes.split(';'), function (FontSize) {
            return FontSize;
        });
    }

    function BuildPluginList(CKEditor5) {
        var PluginNames = [
            'Essentials',
            'Paragraph',
            'Heading',
            'Bold',
            'Italic',
            'Underline',
            'Strikethrough',
            'Subscript',
            'Superscript',
            'Link',
            'AutoLink',
            'List',
            'ListProperties',
            'Indent',
            'IndentBlock',
            'Alignment',
            'Font',
            'FontFamily',
            'FontSize',
            'FontColor',
            'FontBackgroundColor',
            'BlockQuote',
            'Table',
            'TableToolbar',
            'TableProperties',
            'TableCellProperties',
            'Image',
            'ImageBlock',
            'ImageInline',
            'ImageCaption',
            'ImageInsert',
            'ImageResize',
            'ImageStyle',
            'ImageToolbar',
            'ImageUpload',
            'ImageTextAlternative',
            'SimpleUploadAdapter',
            'PasteFromOffice',
            'SourceEditing',
            'GeneralHtmlSupport',
            'RemoveFormat',
            'SpecialCharacters',
            'SpecialCharactersEssentials',
            'FindAndReplace',
            'Mention',
            'HtmlEmbed',
            'Undo'
        ];

        return $.grep($.map(PluginNames, function (PluginName) {
            return CKEditor5[PluginName];
        }), function (Plugin) {
            return !!Plugin;
        });
    }

    function BuildToolbarItems(HasUpload) {
        var ToolbarItems = [
            'undo',
            'redo',
            '|',
            'sourceEditing',
            '|',
            'heading',
            '|',
            'bold',
            'italic',
            'underline',
            'strikethrough',
            'subscript',
            'superscript',
            'removeFormat',
            '|',
            'fontFamily',
            'fontSize',
            'fontColor',
            'fontBackgroundColor',
            '|',
            'alignment',
            '|',
            'bulletedList',
            'numberedList',
            'outdent',
            'indent',
            '|',
            'link',
            'blockQuote',
            'insertTable',
            'htmlEmbed',
            'specialCharacters',
            'findAndReplace'
        ];

        if (HasUpload) {
            ToolbarItems.push('|');
            ToolbarItems.push('insertImage');
            ToolbarItems.push('uploadImage');
        }

        return ToolbarItems;
    }

    function BuildMentionItem(Item, Marker) {
        var Name,
            ID;

        if (typeof Item === 'string') {
            Name = Item;
        }
        else {
            Name = Item.name
                || Item.Name
                || Item.label
                || Item.Label
                || Item.login
                || Item.Login
                || Item.UserLogin
                || Item.GroupName
                || '';
        }

        if (!Name) {
            return;
        }

        ID = Name;

        if (ID.substr(0, Marker.length) !== Marker) {
            ID = Marker + ID;
        }

        return {
            id: ID,
            name: Name,
            text: Name
        };
    }

    function BuildMentionFeed(Marker, Action, Subaction, ResponseKey) {
        return {
            marker: Marker,
            minimumCharacters: 1,
            feed: function (QueryText) {
                return new Promise(function (Resolve) {
                    Core.AJAX.FunctionCall(
                        Core.Config.Get('Baselink'),
                        {
                            Action: Action,
                            Subaction: Subaction,
                            SearchTerm: QueryText
                        },
                        function (Response) {
                            var Items = [],
                                RawItems;

                            if (!Response) {
                                Resolve([]);
                                return;
                            }

                            RawItems = Response[ResponseKey] || [];

                            if ($.isArray(RawItems)) {
                                $.each(RawItems, function () {
                                    var MentionItem = BuildMentionItem(this, Marker);

                                    if (MentionItem) {
                                        Items.push(MentionItem);
                                    }
                                });
                            }
                            else {
                                $.each(RawItems, function () {
                                    var MentionItem = BuildMentionItem(this, Marker);

                                    if (MentionItem) {
                                        Items.push(MentionItem);
                                    }
                                });
                            }

                            Resolve(Items);
                        }
                    );
                });
            }
        };
    }

    function BuildAutocompletionFeed(Trigger, AutocompletionSettings) {
        return {
            marker: Trigger,
            minimumCharacters: AutocompletionSettings.MinSearchLength || 1,
            feed: function (QueryText) {
                return new Promise(function (Resolve) {
                    var AdditionalParams = {
                        TicketID: $('input[name="TicketID"]').val(),
                        Action: $('input[name="Action"]').val(),
                        QueueID: (
                            window.Znuny
                            && Znuny.Form
                            && Znuny.Form.Input
                            && typeof Znuny.Form.Input.Get === 'function'
                        ) ? Znuny.Form.Input.Get('QueueID') : $('select[name="QueueID"], input[name="QueueID"]').val()
                    };

                    Core.AJAX.FunctionCall(
                        Core.Config.Get('Baselink'),
                        {
                            Action: 'AJAXRichTextAutocompletion',
                            Subaction: 'GetData',
                            Trigger: Trigger,
                            SearchString: QueryText,
                            AdditionalParams: AdditionalParams
                        },
                        function (Response) {
                            var Items = [];

                            if (!$.isArray(Response)) {
                                Resolve([]);
                                return;
                            }

                            $.each(Response, function () {
                                var Name = this.name || this.Name || this.label || this.Label || this.id || this.ID || this;

                                if (typeof Name !== 'string') {
                                    return;
                                }

                                Items.push({
                                    id: Trigger + Name,
                                    name: Name,
                                    text: Name
                                });
                            });

                            Resolve(Items);
                        }
                    );
                });
            }
        };
    }

    function GetAutocompletionFeeds() {
        return new Promise(function (Resolve) {
            if (Core.Config.Get('RichText.Type') === 'CodeMirror') {
                Resolve([]);
                return;
            }

            Core.AJAX.FunctionCall(
                Core.Config.Get('Baselink'),
                {
                    Action: 'AJAXRichTextAutocompletion',
                    Subaction: 'GetAutocompletionSettings'
                },
                function (Response) {
                    var Feeds = [];

                    if ($.isEmptyObject(Response) || !Response.Triggers) {
                        Resolve([]);
                        return;
                    }

                    $.each(Response.Triggers, function (Trigger) {

                        // CKEditor 5 mention markers must be single characters.
                        if (!Trigger || Trigger.length !== 1) {
                            return;
                        }

                        Feeds.push(BuildAutocompletionFeed(Trigger, Response));
                    });

                    Resolve(Feeds);
                }
            );
        });
    }

    function GetMentionFeeds() {
        var MentionsConfig = Core.Config.Get('Mentions::RichTextEditor'),
            Feeds = [];

        if (!MentionsConfig || !MentionsConfig.Triggers) {
            return Feeds;
        }

        if (MentionsConfig.Triggers.User) {
            Feeds.push(
                BuildMentionFeed(
                    MentionsConfig.Triggers.User,
                    'Mentions',
                    'GetUsers',
                    'Users'
                )
            );
        }

        if (MentionsConfig.Triggers.Group) {
            Feeds.push(
                BuildMentionFeed(
                    MentionsConfig.Triggers.Group,
                    'Mentions',
                    'GetGroups',
                    'Groups'
                )
            );
        }

        return Feeds;
    }

    function BuildEditorConfig(CKEditor5, $EditorArea, UploadURL, MentionFeeds) {
        var EditorLanguage = GetEditorLanguage(),
            HasUpload = UploadURL ? true : false,
            EditorConfig = {
                licenseKey: Core.Config.Get('RichText.CKEditor5LicenseKey', 'GPL'),
                language: {
                    ui: EditorLanguage,
                    content: EditorLanguage
                },
                toolbar: {
                    items: BuildToolbarItems(HasUpload),
                    shouldNotGroupWhenFull: true
                },
                heading: {
                    options: [
                        {
                            model: 'paragraph',
                            title: 'Paragraph',
                            class: 'ck-heading_paragraph'
                        },
                        {
                            model: 'heading1',
                            view: 'h1',
                            title: 'Heading 1',
                            class: 'ck-heading_heading1'
                        },
                        {
                            model: 'heading2',
                            view: 'h2',
                            title: 'Heading 2',
                            class: 'ck-heading_heading2'
                        },
                        {
                            model: 'heading3',
                            view: 'h3',
                            title: 'Heading 3',
                            class: 'ck-heading_heading3'
                        },
                        {
                            model: 'heading4',
                            view: 'h4',
                            title: 'Heading 4',
                            class: 'ck-heading_heading4'
                        }
                    ]
                },
                fontFamily: {
                    supportAllValues: true
                },
                fontSize: {
                    options: GetFontSizeOptions(),
                    supportAllValues: true
                },
                htmlSupport: {
                    allow: [
                        {
                            name: /.*/,
                            attributes: true,
                            classes: true,
                            styles: true
                        }
                    ]
                },
                link: {
                    addTargetToExternalLinks: false,
                    defaultProtocol: 'https://'
                },
                image: {
                    resizeUnit: 'px',
                    toolbar: [
                        'imageTextAlternative',
                        'toggleImageCaption',
                        '|',
                        'imageStyle:inline',
                        'imageStyle:block',
                        'imageStyle:side',
                        '|',
                        'resizeImage'
                    ]
                },
                table: {
                    contentToolbar: [
                        'tableColumn',
                        'tableRow',
                        'mergeTableCells',
                        'tableProperties',
                        'tableCellProperties'
                    ]
                },
                simpleUpload: {
                    uploadUrl: UploadURL,
                    withCredentials: true
                },
                updateSourceElementOnDestroy: true,
                menuBar: {
                    isVisible: false
                },
                ui: {
                    poweredBy: {
                        position: 'inside',
                        side: 'left',
                        label: ''
                    }
                }
            },
            PluginList = BuildPluginList(CKEditor5);

        if (PluginList.length) {
            EditorConfig.plugins = PluginList;
        }

        if (MentionFeeds && MentionFeeds.length) {
            EditorConfig.mention = {
                feeds: MentionFeeds
            };
        }

        if (!HasUpload) {
            delete EditorConfig.simpleUpload;
        }

        return EditorConfig;
    }

    function SetEditorDimensions(Editor, $EditorArea) {
        var Width = Core.Config.Get('RichText.Width', 620),
            Height = Core.Config.Get('RichText.Height', 320),
            TextDirection = Core.Config.Get('RichText.TextDir', 'ltr'),
            EditableElement,
            EditorElement,
            InitialHeight,
            ResizeStarted = false,
            ApplyEditorHeight,
            RememberEditorHeight,
            IsResizeHandleEvent;

        if (!Editor || !Editor.ui || !Editor.ui.view) {
            return;
        }

        EditorElement = Editor.ui.view.element;
        EditableElement = Editor.ui.view.editable ? Editor.ui.view.editable.element : undefined;

        if (EditorElement) {
            $(EditorElement)
                .find('button, input, select, textarea, [contenteditable="true"]')
                .each(function (Index) {
                    if (!$(this).attr('name')) {
                        $(this).attr('name', 'CKEditor5InternalElement' + Index);
                    }

                    $(this).addClass('IgnoreValidation');
                });
        }

        if (EditorElement && Width) {
            $(EditorElement).css('max-width', Width + 'px');
        }

        if (EditableElement) {
            InitialHeight = parseInt($EditorArea.data('RichTextEditorHeight') || Height, 10);

            if (!InitialHeight || InitialHeight < Height) {
                InitialHeight = Height;
            }

            $EditorArea.data('RichTextEditorHeight', InitialHeight);

            ApplyEditorHeight = function () {
                var StoredHeight = parseInt($EditorArea.data('RichTextEditorHeight') || Height, 10);

                if (!StoredHeight || StoredHeight < Height) {
                    StoredHeight = Height;
                }

                EditableElement.style.setProperty('height', StoredHeight + 'px', 'important');
                EditableElement.style.setProperty('min-height', Height + 'px', 'important');
                EditableElement.style.setProperty('max-height', 'none', 'important');
                EditableElement.style.setProperty('resize', 'vertical', 'important');
                EditableElement.style.setProperty('overflow-y', 'auto', 'important');
                EditableElement.style.setProperty('overflow-x', 'hidden', 'important');
                EditableElement.style.setProperty('box-sizing', 'border-box', 'important');
            };

            RememberEditorHeight = function () {
                var NewHeight = Math.round(EditableElement.getBoundingClientRect().height);

                if (NewHeight >= Height) {
                    $EditorArea.data('RichTextEditorHeight', NewHeight);
                    EditableElement.style.setProperty('height', NewHeight + 'px', 'important');
                }
            };

            IsResizeHandleEvent = function (Event) {
                var Rect = EditableElement.getBoundingClientRect(),
                    Point = Event;

                if (Event.touches && Event.touches.length) {
                    Point = Event.touches[0];
                }

                if (!Point || typeof Point.clientX === 'undefined' || typeof Point.clientY === 'undefined') {
                    return false;
                }

                return Point.clientX >= Rect.right - 24 && Point.clientY >= Rect.bottom - 24;
            };

            ApplyEditorHeight();

            $(EditableElement)
                .attr('dir', TextDirection || 'ltr')
                .off('focusin.RichTextEditorHeight click.RichTextEditorHeight focusout.RichTextEditorHeight blur.RichTextEditorHeight')
                .on('focusin.RichTextEditorHeight click.RichTextEditorHeight', function () {
                    window.setTimeout(function () {
                        ApplyEditorHeight();
                    }, 0);
                })
                .on('focusout.RichTextEditorHeight blur.RichTextEditorHeight', function () {
                    RememberEditorHeight();

                    window.setTimeout(function () {
                        ApplyEditorHeight();
                    }, 0);

                    window.setTimeout(function () {
                        ApplyEditorHeight();
                    }, 50);
                });

            if (!EditableElement.OForkRichTextHeightEvents) {
                EditableElement.OForkRichTextHeightEvents = true;

                EditableElement.addEventListener('mousedown', function (Event) {
                    ResizeStarted = IsResizeHandleEvent(Event);
                });

                EditableElement.addEventListener('touchstart', function (Event) {
                    ResizeStarted = IsResizeHandleEvent(Event);
                });

                document.addEventListener('mouseup', function () {
                    if (!ResizeStarted) {
                        return;
                    }

                    ResizeStarted = false;

                    window.setTimeout(function () {
                        RememberEditorHeight();
                    }, 0);
                });

                document.addEventListener('touchend', function () {
                    if (!ResizeStarted) {
                        return;
                    }

                    ResizeStarted = false;

                    window.setTimeout(function () {
                        RememberEditorHeight();
                    }, 0);
                });
            }

            if (!Editor.OForkRichTextHeightBinding) {
                Editor.OForkRichTextHeightBinding = true;

                Editor.model.document.on('change:data', function () {
                    window.setTimeout(function () {
                        ApplyEditorHeight();
                    }, 0);
                });
            }
        }

        $EditorArea.attr('dir', TextDirection || 'ltr');
    }

    function BindFormSubmit(EditorID) {
        var Instance = Instances[EditorID],
            $Form,
            Namespace;

        if (!Instance) {
            return;
        }

        $Form = Instance.$EditorArea.closest('form');

        if (!$Form.length) {
            return;
        }

        Namespace = '.RichTextEditor' + EditorID.replace(/[^a-zA-Z0-9_-]/g, '');

        $Form.off('submit' + Namespace);
        $Form.on('submit' + Namespace, function () {
            TargetNS.UpdateLinkedField(Instance.$EditorArea);
        });
    }

    function BindEditorEvents(EditorID) {
        var Instance = Instances[EditorID],
            Editor,
            $EditorArea;

        if (!Instance) {
            return;
        }

        Editor = Instance.Editor;
        $EditorArea = Instance.$EditorArea;

        Editor.model.document.on('change:data', function () {
            window.clearTimeout(TimeOutRTEOnChange);

            TimeOutRTEOnChange = window.setTimeout(function () {
                TargetNS.UpdateLinkedField($EditorArea);

                if (Core.Form && Core.Form.Validate) {
                    Core.Form.Validate.ValidateElement($EditorArea);
                }

                Core.App.Publish('Event.UI.RichTextEditor.ChangeValidationComplete', [Instance]);
            }, 250);
        });

        Editor.editing.view.document.on('blur', function () {
            TargetNS.UpdateLinkedField($EditorArea);

            if (!$EditorArea.hasClass('Error') && Core.Form && Core.Form.Validate) {
                Core.Form.Validate.ValidateElement($EditorArea);
            }
        });

        Editor.editing.view.document.on('focus', function () {
            Core.App.Publish('Event.UI.RichTextEditor.Focus', [Instance]);

            if ($EditorArea.attr('class') && $EditorArea.attr('class').match(/Error/)) {
                window.setTimeout(function () {
                    TargetNS.UpdateLinkedField($EditorArea);

                    if (Core.Form && Core.Form.Validate) {
                        Core.Form.Validate.ValidateElement($EditorArea);
                    }

                    Core.App.Publish('Event.UI.RichTextEditor.FocusValidationComplete', [Instance]);
                }, 0);
            }
        });

        $EditorArea.off('focus.RichTextEditor');
        $EditorArea.on('focus.RichTextEditor', function () {
            TargetNS.Focus($EditorArea);
            Core.UI.ScrollTo($('label[for="' + $EditorArea.attr('id') + '"]'));
        });

        BindFormSubmit(EditorID);
    }

    function CreateEditor($EditorArea, CKEditor5, EditorConfig) {
        var EditorConstructor = CKEditor5.ClassicEditor;

        if (!EditorConstructor || typeof EditorConstructor.create !== 'function') {
            Core.Exception.Throw('RichTextEditor: CKEditor 5 ClassicEditor is not available!', 'TypeError');
        }

        return EditorConstructor.create($EditorArea[0], EditorConfig);
    }

    TargetNS.InitEditor = function ($EditorArea) {
        var EditorID,
            UploadURL,
            MentionFeeds;

        if (!IsJQueryObject($EditorArea) || $EditorArea.length !== 1) {
            return false;
        }

        if (Core.Config.Get('RichText.Type') === 'CodeMirror') {
            return false;
        }

        EditorID = GetEditorID($EditorArea);

        if ($EditorArea.hasClass('HasCKEInstance') || Instances[EditorID] || Initializing[EditorID]) {
            return false;
        }

        Initializing[EditorID] = true;
        $EditorArea.addClass('HasCKEInstance');

        if (Core.Config.Get('Mentions::RichTextEditor')) {
            if (!$EditorArea.closest('form').find('input[name="MentionRecipients"]').length) {
                $("<input name='MentionRecipients' type='hidden'>").appendTo($EditorArea.closest('form'));
            }

            if (!$EditorArea.closest('form').find('input[name="MentionGroups"]').length) {
                $("<input name='MentionGroups' type='hidden'>").appendTo($EditorArea.closest('form'));
            }
        }

        UploadURL = BuildUploadURL($EditorArea);
        MentionFeeds = GetMentionFeeds();

        GetCKEditor5Module()
            .then(function (CKEditor5) {
                return GetAutocompletionFeeds().then(function (AutocompletionFeeds) {
                    return {
                        CKEditor5: CKEditor5,
                        Feeds: MentionFeeds.concat(AutocompletionFeeds)
                    };
                });
            })
            .then(function (Data) {
                var EditorConfig = BuildEditorConfig(Data.CKEditor5, $EditorArea, UploadURL, Data.Feeds);

                return CreateEditor($EditorArea, Data.CKEditor5, EditorConfig);
            })
            .then(function (Editor) {
                delete Initializing[EditorID];

                Instances[EditorID] = {
                    ID: EditorID,
                    Editor: Editor,
                    $EditorArea: $EditorArea,
                    UploadURL: UploadURL
                };

                SetEditorDimensions(Editor, $EditorArea);
                BindEditorEvents(EditorID);

                TargetNS.UpdateLinkedField($EditorArea);

                Core.App.Publish('Event.UI.RichTextEditor.InstanceCreated', [Instances[EditorID]]);
                Core.App.Publish('Event.UI.RichTextEditor.InstanceReady', [Instances[EditorID]]);
            })
            .catch(function (Error) {
                delete Initializing[EditorID];

                $EditorArea.removeClass('HasCKEInstance');

                if (window.console && typeof window.console.error === 'function') {
                    window.console.error('RichTextEditor: CKEditor 5 initialization failed.', Error);
                }
            });

        return true;
    };

    TargetNS.InitAllEditors = function () {
        $('textarea.RichText').each(function () {
            TargetNS.InitEditor($(this));
        });
    };

    TargetNS.Init = function () {
        if (!Core.Config.Get('RichTextSet')) {
            return;
        }

        TargetNS.InitAllEditors();
    };

    TargetNS.GetRTE = function ($EditorArea) {
        var EditorID,
            Instance,
            EditorElement;

        if (!IsJQueryObject($EditorArea) || !$EditorArea.length) {
            return;
        }

        EditorID = $EditorArea.attr('id');
        Instance = Instances[EditorID];

        if (!Instance || !Instance.Editor || !Instance.Editor.ui || !Instance.Editor.ui.view) {
            return;
        }

        EditorElement = Instance.Editor.ui.view.element;

        return EditorElement ? $(EditorElement) : undefined;
    };

    TargetNS.UpdateLinkedField = function ($EditorArea) {
        var EditorID,
            Instance,
            Data;

        EditorID = GetEditorID($EditorArea);
        Instance = Instances[EditorID];

        if (!Instance || !Instance.Editor) {
            return;
        }

        if (typeof Instance.Editor.updateSourceElement === 'function') {
            Instance.Editor.updateSourceElement();
        }

        Data = Instance.Editor.getData();

        $EditorArea.val(SanitizeDataForTextarea(Data));
    };

    TargetNS.GetInstance = function (EditorIDOrElement) {
        var EditorID;

        if (typeof EditorIDOrElement === 'string') {
            EditorID = EditorIDOrElement;
        }
        else if (IsJQueryObject(EditorIDOrElement)) {
            EditorID = EditorIDOrElement.attr('id');
        }
        else if (EditorIDOrElement && EditorIDOrElement.id) {
            EditorID = EditorIDOrElement.id;
        }

        if (!EditorID || !Instances[EditorID]) {
            return;
        }

        return Instances[EditorID].Editor;
    };

    TargetNS.GetInstanceData = function (EditorIDOrElement) {
        var EditorID;

        if (typeof EditorIDOrElement === 'string') {
            EditorID = EditorIDOrElement;
        }
        else if (IsJQueryObject(EditorIDOrElement)) {
            EditorID = EditorIDOrElement.attr('id');
        }
        else if (EditorIDOrElement && EditorIDOrElement.id) {
            EditorID = EditorIDOrElement.id;
        }

        return EditorID ? Instances[EditorID] : undefined;
    };

    TargetNS.GetData = function (EditorIDOrElement) {
        var Editor = TargetNS.GetInstance(EditorIDOrElement);

        if (Editor) {
            return Editor.getData();
        }

        if (IsJQueryObject(EditorIDOrElement)) {
            return EditorIDOrElement.val();
        }

        if (typeof EditorIDOrElement === 'string') {
            return $('#' + Core.App.EscapeSelector(EditorIDOrElement)).val();
        }

        return '';
    };

    TargetNS.SetData = function (EditorIDOrElement, Data) {
        var Editor = TargetNS.GetInstance(EditorIDOrElement),
            $EditorArea;

        if (Editor) {
            Editor.setData(Data || '');

            if (typeof Editor.updateSourceElement === 'function') {
                Editor.updateSourceElement();
            }

            return true;
        }

        if (IsJQueryObject(EditorIDOrElement)) {
            EditorIDOrElement.val(Data || '');
            return true;
        }

        if (typeof EditorIDOrElement === 'string') {
            $EditorArea = $('#' + Core.App.EscapeSelector(EditorIDOrElement));

            if ($EditorArea.length) {
                $EditorArea.val(Data || '');
                return true;
            }
        }

        return false;
    };

    TargetNS.HasInstance = function (EditorIDOrElement) {
        var EditorID;

        if (typeof EditorIDOrElement === 'string') {
            EditorID = EditorIDOrElement;
        }
        else if (IsJQueryObject(EditorIDOrElement)) {
            EditorID = EditorIDOrElement.attr('id');
        }
        else if (EditorIDOrElement && EditorIDOrElement.id) {
            EditorID = EditorIDOrElement.id;
        }

        return EditorID && (Instances[EditorID] || Initializing[EditorID]) ? true : false;
    };

    TargetNS.IsEnabled = function ($EditorArea) {
        return TargetNS.HasInstance($EditorArea);
    };

    TargetNS.DestroyInstance = function (EditorIDOrElement) {
        var EditorID,
            Instance,
            Namespace,
            DestroyPromise;

        if (typeof EditorIDOrElement === 'string') {
            EditorID = EditorIDOrElement;
        }
        else if (IsJQueryObject(EditorIDOrElement)) {
            EditorID = EditorIDOrElement.attr('id');
        }
        else if (EditorIDOrElement && EditorIDOrElement.id) {
            EditorID = EditorIDOrElement.id;
        }

        if (!EditorID || !Instances[EditorID]) {
            return Promise.resolve();
        }

        Instance = Instances[EditorID];

        TargetNS.UpdateLinkedField(Instance.$EditorArea);

        Namespace = '.RichTextEditor' + EditorID.replace(/[^a-zA-Z0-9_-]/g, '');
        Instance.$EditorArea.closest('form').off('submit' + Namespace);
        Instance.$EditorArea.off('focus.RichTextEditor');
        Instance.$EditorArea.removeClass('HasCKEInstance');

        DestroyPromise = Instance.Editor.destroy();

        delete Instances[EditorID];
        delete Initializing[EditorID];

        return DestroyPromise;
    };

    TargetNS.DestroyAllEditors = function () {
        var DestroyPromises = [];

        $.each(Instances, function (EditorID) {
            DestroyPromises.push(TargetNS.DestroyInstance(EditorID));
        });

        return Promise.all(DestroyPromises);
    };

    TargetNS.Focus = function ($EditorArea) {
        var EditorID = GetEditorID($EditorArea),
            Instance = Instances[EditorID];

        if (Instance && Instance.Editor && Instance.Editor.editing && Instance.Editor.editing.view) {
            Instance.Editor.editing.view.focus();
            return;
        }

        $EditorArea.focus();
    };

    Core.Init.RegisterNamespace(TargetNS, 'APP_MODULE');

    return TargetNS;
}(Core.UI.RichTextEditor || {}));