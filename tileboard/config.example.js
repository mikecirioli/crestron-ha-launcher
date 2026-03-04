var CONFIG = {
   customTheme: null,
   transition: 'fade',
   tileSize: 150,
   tileMargin: 6,
   
   // YOUR CONNECTION SETTINGS:
   serverUrl: 'http://192.168.1.245:8123',
   wsUrl: 'ws://192.168.1.245:8123/api/websocket',
   authToken: 'YOUR_LONG_LIVED_TOKEN_HERE',

   pages: [
      {
         title: 'Main Page',
         bg: 'images/bg1.jpeg',
         icon: 'mdi-home-outline',
         groups: [
            {
               title: 'Overview',
               width: 2,
               height: 3,
               items: [
                  {
                     position: [0, 0],
                     width: 2,
                     type: TYPES.WEATHER,
                     id: 'weather.cary', // Replace with your actual weather entity
                     state: false,
                     icon: 'clear-day'
                  },
                  {
                     position: [0, 1],
                     type: TYPES.COVER,
                     id: 'cover.wayne_dalton_garage', // Replace with your actual garage door entity
                     title: 'Garage Door',
                     states: {
                        open: 'Open',
                        closed: 'Closed'
                     }
                  },
                  {
                     position: [1, 1],
                     type: TYPES.CAMERA,
                     id: 'camera.front_door', // Your front door camera
                     bgSize: 'cover',
                     width: 1,
                     state: false,
                     fullscreen: {
                        type: TYPES.CAMERA_STREAM,
                        id: 'camera.front_door'
                     }
                  }
               ]
            }
         ]
      }
   ]
};
