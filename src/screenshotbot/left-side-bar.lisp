;;;; Copyright 2018-Present Modern Interpreters Inc.
;;;;
;;;; This Source Code Form is subject to the terms of the Mozilla Public
;;;; License, v. 2.0. If a copy of the MPL was not distributed with this
;;;; file, You can obtain one at https://mozilla.org/MPL/2.0/.

(uiop:define-package :screenshotbot/left-side-bar
  (:use #:cl
        #:alexandria
        #:screenshotbot/user-api)
  (:import-from #:screenshotbot/installation
                #:installation
                #:multi-org-feature)
  (:import-from #:screenshotbot/template
                #:left-side-bar
                #:mdi)
  (:import-from #:screenshotbot/cdn
                #:img)
  (:import-from #:markup
                #:deftag)
  (:import-from #:util
                #:make-url)
  (:import-from #:nibble
                #:nibble)
  (:import-from #:screenshotbot/cdn
                #:img-with-fallback))
(in-package :screenshotbot/left-side-bar)

(markup:enable-reader)

(deftag left-nav-item (children &key href image-class target
                       (script-name (error "need script-name")))
  (let ((activep (str:starts-with-p href script-name)))
    <li class= "nav-item"  >
      <a href= href class= (format nil "nav-link ~a text-white" (if activep "active" "")) >
        <mdi name=image-class />
        <span class= "text">,@children </span>
      </a>
    </li>))

(deftag bs-icon (&key name)
  <img src= (format nil "/assets/images/icons/~a.svg" name) alt=name />)

(defmethod company-switcher ((installation multi-org-feature) &key user)
  <markup:merge-tag>
  ,@ (loop for company in (user-companies user)
           collect
           (let ((company company))
             <li><a href= (nibble () (company-switch-page company)) class="dropdown-item">
             Switch to ,(company-name company)
             </a></li>))
     <li><a class="dropdown-item" href="/organization/new">New Organization...</a></li>

     <li>
       <hr class="dropdown-divider" />
     </li>
  </markup:merge-tag>)

(defmethod company-switcher (installation &key user)
  (declare (ignore user))
  nil)
(deftag left-side-bar (&key user company script-name)
  (declare (optimize (speed 0) (debug 3)))
  <div class="d-flex flex-column text-white bg-dark leftside-menu collapse" >

    <div class= "text-center p-3" >
      <button type= "button" href= "#" class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target=".leftside-menu" aria-controls="navbarSupportedContent" aria-expanded="false" aria-label="Toggle navigation">
        <mdi name= "menu" />
      </button>

      <a href="/" class="align-items-center mb-3 mb-md-0 me-md-auto text-white text-decoration-none">


        <span class="logo logo-lg fs-4">
          <img-with-fallback src= "/assets/images/logo-light-scaled.webp"
                             alt= "Screenshotbot logo"
                             loading= "lazy" />
        </span>
        <span class="logo logo-sm fs-4">
          <img-with-fallback src= "/assets/images/logo-small-light-scaled.webp"
                             alt= "Screenshotbot logo"
                             loading= "lazy" />
        </span>
      </a>
    </div>
  <hr class= "mt-0" >

    <ul class="nav nav-pills flex-column ps-3 pe-3">
      <left-nav-item href= "/runs" image-class= "play_arrow"
                     script-name=script-name >
         Recent Runs
        </left-nav-item>

      <left-nav-item href= "/web-projects" image-class= "cloud_queue"
                      script-name=script-name >
        Web Projects
       </left-nav-item>

      <left-nav-item href= "/channels" image-class= "book"
                     script-name=script-name >
          Channels
      </left-nav-item>

      <left-nav-item href= "/report" image-class= "flag"
                     script-name=script-name >
                         Reports
        </left-nav-item>
    </ul>
    <hr />

    <ul class="nav nav-pills flex-column mb-auto ps-3 pe-3">
      <left-nav-item href= "/documentation" image-class= "menu_book" target= "_blank"
                     script-name=script-name >
        Documentation
  </left-nav-item>

      ,(when (and company (not (singletonp company)))
         <left-nav-item href= "/invite" image-class= "person_add"
                        script-name=script-name >
           Invite Members
         </left-nav-item>)


      <left-nav-item href= "/api-keys" image-class= "vpn_key"
                     script-name=script-name >
        API Keys
      </left-nav-item>

      ,(progn
         #-screenshotbot-oss
         <left-nav-item href= "/billing/dashboard" image-class= "payment"
                        script-name=script-name >
           Billing
         </left-nav-item>)

      ,(when user
         #-screenshotbot-oss
         <left-nav-item href= "/ticket/create" image-class= "report"
                        script-name=script-name >
                        Report Issue
         </left-nav-item>)
    </ul>

    <hr class= "mb-0" />
    ,(when user
    <div class="dropdown p-3">
      <a href="#" class="d-flex align-items-center text-white text-decoration-none dropdown-toggle" id="dropdownUser1" data-bs-toggle="dropdown" aria-expanded="false">
        <img src= (user-image-url user) alt="mdo" width="32" height="32" class="rounded-circle me-2">
          <strong class= "user-full-name" > ,(cond
                      ((or (not company) (singletonp company) (personalp company))
                       (user-full-name user))
                      (t
                       (company-name company))) </strong>
      </a>
      <ul class="dropdown-menu dropdown-menu-dark text-small shadow multi-level" aria-labelledby="dropdownUser1">
        ,(company-switcher (installation) :user user)

        <li><a class="dropdown-item" href="/settings/general">Settings</a></li>
        ,(when (adminp user)
           <li>
	         <a href="/admin" class="dropdown-item notify-item">
	           <span>Admin</span>
	      </a>
           </li>)

        <li><a class="dropdown-item signout-link" href="/signout">Sign out</a></li>
      </ul>
    </div>
    )
  </div>)
