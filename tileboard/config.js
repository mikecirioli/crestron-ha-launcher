// 1. SETTINGS
var MAX_IMAGES = 1443; 
var activeCamIndex = 0;
var HA_URL = 'http://homeassistant.local:8123';

// 2. PRE-BUILD THE SLIDE DECK
var mySlideDeck = [];
for (var i = 0; i < 500; i++) {
   var num = Math.floor(Math.random() * MAX_IMAGES) + 1;
   mySlideDeck.push({ bg: HA_URL + '/local/ciriolisaver/' + num + '.jpg' });
}

// 3. ROTATION LOGIC
setInterval(function() {
    activeCamIndex = (activeCamIndex + 1) % 5; 
    var el = document.querySelector('[ng-app]');
    if (el) { angular.element(el).scope().$evalAsync(); }
}, 12000); 

var CONFIG = {
   tileSize: 130, 
   tileMargin: 8,
   serverUrl: HA_URL,
   wsUrl: 'ws://homeassistant.local:8123/api/websocket',
   authToken: '',  // Set via deployment, not committed

   screensaver: {
      timeout: 30, // Activates after 30 seconds
      slidesTimeout: 10, // Cycles every 10 seconds
      styles: { fontSize: '40px', color: '#ffffff' },
      leftBottom: [{ type: TYPES.DATETIME }], 
      bgSize: 'cover', 
      slides: mySlideDeck 
   },

   pages: [{
      title: 'Home',
      bg: null, 
      styles: { backgroundColor: '#000000' },
      groups: [
         {
            title: 'Overview',
            width: 2,
            items: [
               { 
                  // ALIGNMENT: Added '-compact' to shrink the giant temperature font
                  position: [0, 0], width: 1, type: TYPES.WEATHER, 
                  id: 'weather.forecast_home', 
                  state: false, 
                  classes: ['-compact'], 
                  fields: { 
                     summary: '&weather.forecast_home.state', 
                     temperature: '&weather.forecast_home.attributes.temperature' 
                  } 
               },
               { position: [1, 0], type: TYPES.CLIMATE, id: 'climate.upper_level' }
               // Test Saver button is fully removed
            ]
         },
         {
            title: 'Switches',
            width: 2,
            items: [
               { position: [0, 0], type: TYPES.LIGHT, id: 'light.ceiling_light_rgbcw_8f2721', title: 'Sink' },
               { position: [1, 0], type: TYPES.SWITCH, id: 'switch.smart_plug_3', title: 'Tree' },
               { position: [0, 1], type: TYPES.SWITCH, id: 'switch.smart_plug', title: 'Fountain' },
               { 
                  position: [1, 1], type: TYPES.POPUP, id: 'switch.smart_plug_2', title: 'Pond', 
                  icon: function(item, entity) { return entity.state === 'on' ? 'mdi-water' : 'mdi-water-off'; }, 
                  popup: { items: [{ position: [0, 0], type: TYPES.SWITCH, id: 'switch.plug_2', title: 'Confirm Toggle' }] } 
               }
            ]
         },
         {
            title: 'Live View',
            width: 3,
            items: [
               { position: [0, 0], width: 3, height: 2, type: TYPES.CAMERA, id: 'camera.frontporch', bgSize: 'contain', hidden: function() { return activeCamIndex !== 0; }, fullscreen: { type: TYPES.CAMERA, id: 'camera.front_porch_main', refresh: 500, bgSize: 'contain' } },
               { position: [0, 0], width: 3, height: 2, type: TYPES.CAMERA, id: 'camera.driveway', bgSize: 'contain', hidden: function() { return activeCamIndex !== 1; }, fullscreen: { type: TYPES.CAMERA, id: 'camera.driveway_main', refresh: 500, bgSize: 'contain' } },
               { position: [0, 0], width: 3, height: 2, type: TYPES.CAMERA, id: 'camera.armory', bgSize: 'contain', hidden: function() { return activeCamIndex !== 2; }, fullscreen: { type: TYPES.CAMERA, id: 'camera.armory_main', refresh: 500, bgSize: 'contain' } },
               { position: [0, 0], width: 3, height: 2, type: TYPES.CAMERA, id: 'camera.pancam', bgSize: 'contain', hidden: function() { return activeCamIndex !== 3; }, fullscreen: { type: TYPES.CAMERA, id: 'camera.pancam_main', refresh: 500, bgSize: 'contain' } },
               { position: [0, 0], width: 3, height: 2, type: TYPES.CAMERA, id: 'camera.gatetown', bgSize: 'contain', hidden: function() { return activeCamIndex !== 4; }, fullscreen: { type: TYPES.CAMERA, id: 'camera.gatetown_main', refresh: 500, bgSize: 'contain' } }
            ]
         }
      ]
   }]
};
