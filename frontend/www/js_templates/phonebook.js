// name
// parent-name
// street
// city-state-zip
// description
// contacts: [
//   { name: '', phone: '', email: '' }
// ]
// children-names: [
//   ''
// ]
//

document.addEventListener('DOMContentLoaded', function() {

  let url = new URL(window.location.href);
  let entityID = url.searchParams.get('entity_id');

  loadEntityList(entityID);

  // let map = new NDDIMap('map');
  // map.on("loaded", function(){
  //   this.updateMapFromSession(session);
  // });

  // map.on("clickNode", function(e, args) {
  //   let node = args[0].name;
  //   loadEndpointSelectionModal(node);
  //   loadEndpointSelectionInterfaces(node);
  // });
});

async function loadEntityList(parentEntity=null) {
    let entity = await getEntities(session.data.workgroup_id, parentEntity);
    let entitiesList = document.querySelector('#entity-list');

    let logoURL = entity.logo_url || 'https://shop.lego.com/static/images/svg/lego-logo.svg';
    let description = entity.description;
    let name = entity.name;
    let entityID = entity.entity_id;

    let parent = null;
    if ('parents' in entity && entity.parents.length > 0) {
        parent = entity.parents[0];
    }

    let logo = document.querySelector('.entity-logo');
    logo.setAttribute('src', logoURL);

    let entityName = document.querySelector('#entity-name');
    if (parent !== null) {
        entityName.innerHTML = `${name} <small>of <a href="#" onclick="loadEntityList(${parent.entity_id})">${parent.name}</a></small>`;
    } else {
        entityName.innerHTML = name;
    }

    let entityConnect = document.querySelector('#entity-connect');
    if (parent !== null) {
        entityConnect.style.display = 'block';
        entityConnect.innerHTML = `Connect to ${name}`;
    } else {
        entityConnect.style.display = 'none';
    }

    let entityDescription = document.querySelector('#entity-description');
    entityDescription.innerHTML = description;

    let entityNav = '';
    if (parent !== null) {
        entityNav += `<li role="presentation" onclick="loadEntityList(${parent.entity_id})"><a href="#">&lt; ${parent.name}</a></li>`;
    }

    entity.children.forEach(function(entity) {
            let childLi  = `<li role="presentation" onclick="loadEntityList(${entity.entity_id})"><a href="#">${entity.name} &gt;</a></li>`;
            entityNav += childLi;
    });

    entitiesList.innerHTML = entityNav;
}
