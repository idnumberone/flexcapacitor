
package com.flexcapacitor.services {
	
	import flash.events.Event;
	import flash.events.EventDispatcher;
	import flash.events.HTTPStatusEvent;
	import flash.events.IEventDispatcher;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.net.URLRequestMethod;
	import flash.net.URLVariables;
	import flash.utils.getTimer;
	
	
	/**
	 * The event that is dispatched on results. 
	 * */
	[Event(name="result", type="com.flexcapacitor.services.WPServiceEvent")]
	
	/**
	 * The event that is dispatched on fault. 
	 * */
	[Event(name="fault", type="com.flexcapacitor.services.WPServiceEvent")]
	
	/**
	 * An adapter class and service to save data to WordPress. <br/><br/>
	 * 
	 * This class works with the JSON API for WordPress. <br/><br/>
	 * 
	 * Notes:<br/><br/>
	 * 
	 * Be sure WordPress auto formatting is off - this automatically adds Paragraph tags around your content. This is called wpautop. <br/>
	 * Also be sure fancy quotes is off - it automatically adds curly quotes when it encounters them in your content.<br/>
	 * There are plugins out there that will remove WP autoformatting<br/>
	 * There are plugins that will interfere with the JSON results as well<br/><br/>
	 * 
	 * Error #1132: Invalid JSON parse input.<br/>
	 * - check the text property of the event to see the original source. <br/><br/>
	 * 
	 * If you can't update or create posts be sure that the user is 
	 * logged in with Editor or Author permissions
	 * and check if the Posts option is enabled in the JSON-API settings page. <br/>
	 * 
	 * @see WPService
	 * @see WPAttachmentService
	 * */
	public class WPServiceBase extends EventDispatcher implements IWPService {
		
		/**
		 * Constructor
		 * */
		public function WPServiceBase(target:IEventDispatcher=null) {
			super(target);
			
			if (loader==null) {
				loader = new URLLoader();
				loader.dataFormat = URLLoaderDataFormat.TEXT;
				addEventListeners(loader);
			}
			
			if (request==null) {
				request = new URLRequest();
			}
			
		}
		
		/**
		 * Constants
		 * */
		public static const RESULT:String = "result";
		public static const FAULT:String = "fault";
		
		/**
		 * URLLoader to communicate with the server
		 * */
		public var loader:URLLoader;
		
		/**
		 * URLRequest to communicate with the server
		 * */
		public var request:URLRequest;

		/**
		 * URL to Wordpress blog with trailing slash. For example,
		 * http://www.radii8.com/blog/
		 * */
		public var host:String;
		
		private var _url:String;

		/**
		 * URL to call. Prepends the host to the value passed in. 
		 * Also sets the request.data to null so we don't have
		 * to do this on every call. 
		 * */
		public function get url():String {
			return _url;
		}

		/**
		 * @private
		 */
		public function set url(value:String):void {
			_url = host + value;
			
			if (request) {
				request.url = _url;
				request.data = null;
			}
		}

		
		public var time:int;
		
		public var parseTime:int;

		public var responseTime:int;
		
		public var updateToken:String;
		
		public var createToken:String;
		
		protected var uploadPending:Boolean;
		
		protected var updatePending:Boolean;
		
		protected var createPending:Boolean;
		
		protected var deletePending:Boolean;
		
		/**
		 * Data returned from the server
		 * */
		[Bindable]
		public var data:Object;
		
		/**
		 * Data to save to the server. Flash will convert the 
		 * parameters object to a string if the method type is set to GET.
		 * Changed the type to URLVariables and method to POST. 
		 * */
		public var parameters:URLVariables;
		
		/**
		 * ID of post to save to
		 * */
		public var id:String;
		
		/**
		 * Call being made
		 * */
		public var call:String;
		
		/**
		 * Indicates if a call is in progress
		 * */
		[Bindable]
		public var inProgress:Boolean;
		
		/**
		 * Call method where you specify the controller, method and add parameters
		 * query - list of additional get parameters. for example, "&count=10&category=news"
		 * post - object to send to the server. 
		 * @see query
		 * */
		public function send(controller:String = "core", method:String = "get_recent_posts", query:String="", post:Object = null):void {
			url = "?json=" + controller + "/" + method + query;
			request.method = URLRequestMethod.POST;
			request.data = post;
			request.url = url;
			load(request);
		}
		
		/**
		 * Call method where you manually specify everything in the query including controller, method and parameters
		 * query - list of additional get parameters. for example, "?json=posts/get_recent_posts&count=10"
		 * post - object to send to the server. 
		 * @see send
		 * */
		public function query(query:String="?json=1", post:Object = null):void {
			url = query;
			request.method = URLRequestMethod.POST;
			request.data = post;
			request.url = url;
			load(request);
		}
		
		/**
		 * Load request. We wrap the load call to cancel previous operations.
		 * */
		public function load(request:URLRequest = null):void {
			
			// close call if open
			try {
				loader.close();
			}
			catch (e:Error) {
				// we don't care
				//trace("loader not in progress");
			}
			
			loader.load(request);
		}
	
		/**
		 * Fault handler
		 * */
		public function onFault(event:Event):void {
			var serviceEvent:WPServiceEvent = new WPServiceEvent(WPServiceEvent.FAULT);
			serviceEvent.call = call;
			serviceEvent.faultEvent = event;
			//serviceEvent.faultCode = event.fault.faultCode;
			//serviceEvent.message = "Could not create update token";
			inProgress = false;
			createPending = false;
			updatePending = false;
			uploadPending = false;
			deletePending = false;
			dispatchEvent(serviceEvent);
		}
		
		/**
		 * Result handler
		 * */
		public function onResult(data:Object, event:Event = null):void {
			var result:String = data as String;
			var serviceEvent:WPServiceEvent;
			var currentTime:int;
			var json:Object;
			var token:String;
			var anotherCallToGo:Boolean;
			var profile:Boolean;
			
			profile ? responseTime = getTimer() - time :-3;
			
			serviceEvent = new WPServiceEvent(WPServiceEvent.RESULT);
			serviceEvent.call = call;
			serviceEvent.text = result;
			serviceEvent.resultEvent = event;
			
			try {
				profile ? currentTime = getTimer():-0;
				json = JSON.parse(result);
				profile ? parseTime = getTimer()- currentTime:-(1);
				
			}
			catch (e:Error) {
				// Error #1132: Invalid JSON parse input.
				serviceEvent.resultEvent = event;
				serviceEvent.parseError = e;
				serviceEvent.data = json;
				serviceEvent.message = "Parse result error";
				
				inProgress = false;
				createPending = false;
				updatePending = false;
				uploadPending = false;
				deletePending = false;
				
				dispatchEvent(serviceEvent);
				
				return;
			}
		
			if (json && json is Object && "nonce" in json) {
				token = json.nonce;
			}
			else if (json==null) {
				serviceEvent.message = "JSON object is null";
			}
			
			if (json) {
				serviceEvent.data = json;
			}
			
			if (json && json is Object && "status" in json && json.status=="error") {
				serviceEvent.message = "Update token error";
				dispatchEvent(serviceEvent);
			}
			else if (updatePending) {
				updatePost(token);
				anotherCallToGo = true;
			}
			else if (createPending) {
				createPost(token);
				anotherCallToGo = true;
			}
			else if (deletePending) {
				deletePost(token);
				anotherCallToGo = true;
			}
			else if (uploadPending) {
				uploadAttachment(token);
				anotherCallToGo = true;
			}
			
			inProgress = false;
			createPending = false;
			updatePending = false;
			uploadPending = false;
			deletePending = false;
			
			if (!anotherCallToGo) {
				dispatchEvent(serviceEvent);
			}
		}
		
		/**
		 * Creates a post. Stub method.
		 * */
		public function createPost(currentToken:String = null):void {
			inProgress = true;
		}
		
		/**
		 * Updates a post. Stub method.
		 * */
		public function updatePost(currentToken:String = null):void {
			inProgress = true;
		}
		
		/**
		 * Deletes a post. Stub method.
		 * */
		public function deletePost(currentToken:String = null):void {
			inProgress = true;
		}
		
		/**
		 * Uploads an attachment. Stub method.
		 * */
		public function uploadAttachment(currentToken:String = null):void {
			inProgress = true;
		}
		
		/**
		 * Save
		 * */
		public function save(data:URLVariables = null):void {
			inProgress = true;
		}
		
		
		/**
		 * Add event listeners to the URLLoader instance
		 * */
		protected function addEventListeners(dispatcher:IEventDispatcher):void {
            dispatcher.addEventListener(Event.COMPLETE, completeHandler, false, 0, true);
            dispatcher.addEventListener(Event.OPEN, openHandler, false, 0, true);
            dispatcher.addEventListener(ProgressEvent.PROGRESS, progressHandler, false, 0, true);
            dispatcher.addEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler, false, 0, true);
            dispatcher.addEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler, false, 0, true);
            dispatcher.addEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler, false, 0, true);
        }
		
		/**
		 * Remove event listeners from URLLoader instance.
		 * */
		protected function removeEventListeners(dispatcher:IEventDispatcher):void {
            dispatcher.removeEventListener(Event.COMPLETE, completeHandler);
            dispatcher.removeEventListener(Event.OPEN, openHandler);
            dispatcher.removeEventListener(ProgressEvent.PROGRESS, progressHandler);
            dispatcher.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, securityErrorHandler);
            dispatcher.removeEventListener(HTTPStatusEvent.HTTP_STATUS, httpStatusHandler);
            dispatcher.removeEventListener(IOErrorEvent.IO_ERROR, ioErrorHandler);
		}
		
		//--------------------------------------------------------------------------
		//
		//  Event handlers
		//
		//--------------------------------------------------------------------------
		
		/**
		 * URL Loader complete
		 * */
		protected function completeHandler(event:Event):void {
			//ObjectUtil.toString(event.currentTarget);
			onResult(loader.data, event);
		}

		/**
		 * 
		 * */
        protected function openHandler(event:Event):void {
            //trace("openHandler: " + event);
        }

		/**
		 * 
		 * */
        protected function progressHandler(event:ProgressEvent):void {
            //trace("progressHandler loaded:" + event.bytesLoaded + " total: " + event.bytesTotal);
        }

		/**
		 * 
		 * */
        protected function httpStatusHandler(event:HTTPStatusEvent):void {
           // trace("httpStatusHandler: " + event);
        }
		
		/**
		 * IO Error handler
		 * */
		protected function ioErrorHandler(event:IOErrorEvent):void {
			onFault(event);
		}
		
		/**
		 * Security Error handler
		 * */
		protected function securityErrorHandler(event:SecurityErrorEvent):void {
			onFault(event);
		}
	}
}