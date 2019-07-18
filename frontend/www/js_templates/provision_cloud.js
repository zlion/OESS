class GlobalState extends Component {
  constructor(state) {
    super();
    this.connection = {
      id:        -1,
      endpoints: []
    };
  }

  async selectConnection(id) {
    if (id != -1) {
      // this.connection = await getCircuit(id);
    }
    update();
  }

  updateEndpoint(e) {
    if (e.index < 0) {
      this.connection.endpoints.push(e);
    } else {
      this.connection.endpoints[e.index] = e;
    }
    update();
  }

  deleteEndpoint(i) {
    this.connection.endpoints.splice(i, 1);
    update();
  }

  deletePeering(endpointIndex, peeringIndex) {
    this.connection.endpoints[endpointIndex].peers.splice(peeringIndex, 1);
  }

  async save() {
    console.log('Connection:', this.connection);

    if (!document.querySelector('#description').validity.valid) {
      document.querySelector('#description').reportValidity();
      return;
    }

    let addNetworkLoadingModal = $('#add-network-loading');
    addNetworkLoadingModal.modal('show');

    try {
      let vrfID = await provisionVRF(
        session.data.workgroup_id,
        document.querySelector('#description').value,
        document.querySelector('#description').value,
        this.connection.endpoints,
        schedule.createTime(),
        schedule.removeTime(),
        -1
      );

      if (vrfID === null) {
        addNetworkLoadingModal.modal('hide');
      } else {
        window.location.href = `index.cgi?action=view_l3vpn&vrf_id=${vrfID}`;
      }
    } catch (error){
      addNetworkLoadingModal.modal('hide');
      alert('Failed to provision L3VPN: ' + error);
      return;
    }
  }

  cancel() {
    if (!window.confirm('Are you sure you wish to cancel? All your changes will be lost.')) {
      return;
    }
    window.location.href = 'index.cgi';
  }
}


let state = new GlobalState();

let schedule = new Schedule('#schedule-picker');
let modal = new EndpointSelectionModal2('#endpoint-selection-modal');


async function update(props) {
  console.log(state);

  let list = document.getElementById('endpoints2-list');
  list.innerHTML = '';

  state.connection.endpoints.map(function(e, i) {
    e.index = i;
    e.peers = ('peers' in e) ? e.peers : [];

    let endpoint = new Endpoint2('#endpoints2-list', e);
    e.peers.map(function(p, j) {
      p.index = j;
      p.endpointIndex = i;
      let peeringElem = endpoint.peerings();

      let peering = new Peering2(peeringElem, p);
      peering.onDelete(function(peering) {
        state.deletePeering(i, j);
        update();
      });
    });
  });
}


document.addEventListener('DOMContentLoaded', function() {
  loadUserMenu();

  let addNetworkEndpoint = document.querySelector('#new-endpoint-button');
  addNetworkEndpoint.addEventListener('click', function(event) {
    modal.display(null);
  });

  let addNetworkSubmit = document.querySelector('#save-button');
  addNetworkSubmit.addEventListener('click', async function(event) {
    state.save();
  });

  let addNetworkCancel = document.querySelector('#cancel-button');
  addNetworkCancel.addEventListener('click', function(event) {
    window.location.href = 'index.cgi?action=welcome';
  });

  let url = new URL(window.location.href);
  let id = url.searchParams.get('prepop_vrf_id');
  if (id) {
      showAndPrePopulateEndpointSelectionModal(id);
  }
});


function setIPv4ValidationMessage(input) {
    input.addEventListener('input', function(e) {
        if (input.validity.valueMissing) {
            input.setCustomValidity('Please fill out this field.');
        } else if (input.validity.patternMismatch) {
            input.setCustomValidity('Please input a valid IPv4 subnet in CIDR notation.');
        } else {
            input.setCustomValidity('');
        }
    }, false);
}


function loadPeerFormValidator(index) {
  let ipVersion =  document.querySelector(`#new-peering-form-${index} .ip-version`);
  if (ipVersion.checked) {
    let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);
    asIPv6CIDR(yourPeerIP);

    let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
    asIPv6CIDR(oessPeerIP);
  } else {
    let yourPeerIP = document.querySelector(`#new-peering-form-${index} .your-peer-ip`);
    asIPv4CIDR(yourPeerIP);

    let oessPeerIP = document.querySelector(`#new-peering-form-${index} .oess-peer-ip`);
    asIPv4CIDR(oessPeerIP);
  }
}
